-- Read-only postflight verification for migrations 076, 077, and 078.
-- Run in the Supabase Dashboard SQL Editor after all three migrations succeed.
-- This file reads PostgreSQL catalogs and aggregate metadata only. It does not
-- invoke application RPCs or inspect inquiry subjects, bodies, or user IDs.

-- Index definitions and partial predicates.
select
  ic.relname as index_name,
  tc.relname as table_name,
  i.indisvalid as is_valid,
  pg_catalog.pg_get_indexdef(ic.oid) as index_definition,
  pg_catalog.pg_get_expr(i.indpred, i.indrelid) as predicate
from pg_catalog.pg_class as ic
join pg_catalog.pg_namespace as n
  on n.oid = ic.relnamespace
join pg_catalog.pg_index as i
  on i.indexrelid = ic.oid
join pg_catalog.pg_class as tc
  on tc.oid = i.indrelid
where n.nspname = 'public'
  and ic.relname in (
    'class_inquiries_author_updated_idx',
    'class_inquiries_class_updated_idx',
    'class_inquiries_class_status_updated_idx',
    'class_inquiries_class_unanswered_idx',
    'class_inquiries_class_staff_unread_idx',
    'class_inquiries_author_parent_unread_idx',
    'class_inquiry_messages_inquiry_created_idx'
  )
order by ic.relname;

-- Policy commands, target roles, and effective predicates.
select
  c.relname as table_name,
  p.polname as policy_name,
  p.polcmd as command_code,
  array(
    select pg_catalog.pg_get_userbyid(role_oid)
    from unnest(p.polroles) as policy_role(role_oid)
    order by pg_catalog.pg_get_userbyid(role_oid)
  ) as target_roles,
  pg_catalog.pg_get_expr(p.polqual, p.polrelid) as qual,
  pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) as with_check
from pg_catalog.pg_policy as p
join pg_catalog.pg_class as c
  on c.oid = p.polrelid
join pg_catalog.pg_namespace as n
  on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in (
    'class_inquiry_daily_counters',
    'class_inquiries',
    'class_inquiry_messages'
  )
order by c.relname, p.polname;

-- RPC and append-only function security, owner, ACL, configuration, and result.
select
  p.oid::regprocedure::text as signature,
  p.prosecdef as security_definer,
  p.proconfig as configuration,
  pg_catalog.pg_get_userbyid(p.proowner) as function_owner,
  p.proacl as execute_acl,
  pg_catalog.pg_get_function_result(p.oid) as return_type
from pg_catalog.pg_proc as p
join pg_catalog.pg_namespace as n
  on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.oid in (
    pg_catalog.to_regprocedure('public.reject_class_inquiry_message_mutation()'),
    pg_catalog.to_regprocedure('public.create_class_inquiry(uuid,text,text,text,uuid)'),
    pg_catalog.to_regprocedure('public.add_parent_class_inquiry_message(uuid,text,uuid)'),
    pg_catalog.to_regprocedure('public.reply_to_class_inquiry(uuid,text,uuid)'),
    pg_catalog.to_regprocedure('public.start_class_inquiry_review(uuid)'),
    pg_catalog.to_regprocedure('public.close_class_inquiry(uuid,uuid)'),
    pg_catalog.to_regprocedure('public.mark_class_inquiry_parent_read(uuid)'),
    pg_catalog.to_regprocedure('public.mark_class_inquiry_staff_read(uuid)'),
    pg_catalog.to_regprocedure('public.get_my_class_inquiries(uuid,text,boolean,timestamptz,uuid,integer)'),
    pg_catalog.to_regprocedure('public.get_class_inquiries_for_staff(uuid,text,boolean,boolean,boolean,timestamptz,uuid,integer)'),
    pg_catalog.to_regprocedure('public.get_class_inquiry_thread(uuid)')
  )
order by p.oid::regprocedure::text;

-- Direct table and column ACL entries for the four roles under review.
select
  'table'::text as acl_scope,
  c.relname as table_name,
  null::text as column_name,
  case when acl.grantee = 0 then 'PUBLIC' else pg_catalog.pg_get_userbyid(acl.grantee) end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_catalog.pg_class as c
join pg_catalog.pg_namespace as n
  on n.oid = c.relnamespace
cross join lateral pg_catalog.aclexplode(c.relacl) as acl
where n.nspname = 'public'
  and c.relname in (
    'class_inquiry_daily_counters',
    'class_inquiries',
    'class_inquiry_messages'
  )
  and acl.grantee in (
    0::oid,
    pg_catalog.to_regrole('anon')::oid,
    pg_catalog.to_regrole('authenticated')::oid,
    pg_catalog.to_regrole('service_role')::oid
  )

union all

select
  'column',
  c.relname,
  a.attname,
  case when acl.grantee = 0 then 'PUBLIC' else pg_catalog.pg_get_userbyid(acl.grantee) end,
  acl.privilege_type,
  acl.is_grantable
from pg_catalog.pg_class as c
join pg_catalog.pg_namespace as n
  on n.oid = c.relnamespace
join pg_catalog.pg_attribute as a
  on a.attrelid = c.oid
 and a.attnum > 0
 and not a.attisdropped
cross join lateral pg_catalog.aclexplode(a.attacl) as acl
where n.nspname = 'public'
  and c.relname in (
    'class_inquiry_daily_counters',
    'class_inquiries',
    'class_inquiry_messages'
  )
  and acl.grantee in (
    0::oid,
    pg_catalog.to_regrole('anon')::oid,
    pg_catalog.to_regrole('authenticated')::oid,
    pg_catalog.to_regrole('service_role')::oid
  )
order by acl_scope, table_name, column_name, grantee, privilege_type;

-- Assertion report is intentionally last so the SQL Editor displays it last.
with
expected_tables(table_name) as (
  values
    ('class_inquiry_daily_counters'::text),
    ('class_inquiries'::text),
    ('class_inquiry_messages'::text)
),
expected_columns(table_name, column_names) as (
  values
    (
      'class_inquiry_daily_counters'::text,
      array[
        'center_id',
        'document_date',
        'last_value',
        'updated_at'
      ]::text[]
    ),
    (
      'class_inquiries'::text,
      array[
        'id',
        'class_id',
        'center_id',
        'author_id',
        'create_request_key',
        'document_date',
        'daily_sequence',
        'document_no',
        'category',
        'subject',
        'status',
        'created_at',
        'updated_at',
        'last_message_at',
        'last_parent_message_at',
        'last_staff_message_at',
        'parent_last_read_at',
        'staff_last_read_at',
        'answered_at',
        'closed_at',
        'closed_by_id',
        'closed_by_role'
      ]::text[]
    ),
    (
      'class_inquiry_messages'::text,
      array[
        'id',
        'inquiry_id',
        'sender_id',
        'sender_role',
        'message_type',
        'body',
        'status_from',
        'status_to',
        'request_key',
        'created_at'
      ]::text[]
    )
),
expected_constraints(table_name, constraint_name, constraint_type) as (
  values
    ('class_inquiry_daily_counters', 'class_inquiry_daily_counters_pkey', 'p'::text),
    ('class_inquiry_daily_counters', 'class_inquiry_daily_counters_center_id_fkey', 'f'::text),
    ('class_inquiry_daily_counters', 'class_inquiry_daily_counters_last_value_check', 'c'::text),

    ('class_inquiries', 'class_inquiries_pkey', 'p'::text),
    ('class_inquiries', 'class_inquiries_class_id_fkey', 'f'::text),
    ('class_inquiries', 'class_inquiries_center_id_fkey', 'f'::text),
    ('class_inquiries', 'class_inquiries_author_id_fkey', 'f'::text),
    ('class_inquiries', 'class_inquiries_closed_by_id_fkey', 'f'::text),
    ('class_inquiries', 'class_inquiries_create_request_key_key', 'u'::text),
    ('class_inquiries', 'class_inquiries_document_no_key', 'u'::text),
    ('class_inquiries', 'class_inquiries_center_document_sequence_key', 'u'::text),
    ('class_inquiries', 'class_inquiries_daily_sequence_check', 'c'::text),
    ('class_inquiries', 'class_inquiries_document_no_check', 'c'::text),
    ('class_inquiries', 'class_inquiries_category_check', 'c'::text),
    ('class_inquiries', 'class_inquiries_subject_check', 'c'::text),
    ('class_inquiries', 'class_inquiries_status_check', 'c'::text),
    ('class_inquiries', 'class_inquiries_closed_by_role_check', 'c'::text),
    ('class_inquiries', 'class_inquiries_closed_state_consistency_check', 'c'::text),
    ('class_inquiries', 'class_inquiries_updated_at_check', 'c'::text),
    ('class_inquiries', 'class_inquiries_last_message_at_check', 'c'::text),
    ('class_inquiries', 'class_inquiries_last_parent_message_at_check', 'c'::text),
    ('class_inquiries', 'class_inquiries_last_staff_message_at_check', 'c'::text),
    ('class_inquiries', 'class_inquiries_parent_last_read_at_check', 'c'::text),
    ('class_inquiries', 'class_inquiries_staff_last_read_at_check', 'c'::text),
    ('class_inquiries', 'class_inquiries_answered_at_check', 'c'::text),
    ('class_inquiries', 'class_inquiries_closed_at_check', 'c'::text),

    ('class_inquiry_messages', 'class_inquiry_messages_pkey', 'p'::text),
    ('class_inquiry_messages', 'class_inquiry_messages_inquiry_id_fkey', 'f'::text),
    ('class_inquiry_messages', 'class_inquiry_messages_sender_id_fkey', 'f'::text),
    ('class_inquiry_messages', 'class_inquiry_messages_request_key_key', 'u'::text),
    ('class_inquiry_messages', 'class_inquiry_messages_sender_role_check', 'c'::text),
    ('class_inquiry_messages', 'class_inquiry_messages_message_type_check', 'c'::text),
    ('class_inquiry_messages', 'class_inquiry_messages_body_check', 'c'::text),
    ('class_inquiry_messages', 'class_inquiry_messages_status_from_check', 'c'::text),
    ('class_inquiry_messages', 'class_inquiry_messages_status_to_check', 'c'::text),
    ('class_inquiry_messages', 'class_inquiry_messages_status_pair_check', 'c'::text),
    ('class_inquiry_messages', 'class_inquiry_messages_status_transition_check', 'c'::text),
    ('class_inquiry_messages', 'class_inquiry_messages_status_change_check', 'c'::text)
),
expected_constraint_semantics(constraint_name, required_fragments) as (
  values
    (
      'class_inquiry_daily_counters_pkey'::text,
      array['center_id', 'document_date']::text[]
    ),
    (
      'class_inquiries_pkey'::text,
      array['id']::text[]
    ),
    (
      'class_inquiries_create_request_key_key'::text,
      array['create_request_key']::text[]
    ),
    (
      'class_inquiries_document_no_key'::text,
      array['document_no']::text[]
    ),
    (
      'class_inquiries_center_document_sequence_key'::text,
      array['center_id', 'document_date', 'daily_sequence']::text[]
    ),
    (
      'class_inquiries_category_check'::text,
      array['category', 'general', 'attendance', 'health', 'schedule', 'supplies', 'other']::text[]
    ),
    (
      'class_inquiries_status_check'::text,
      array['status', 'received', 'in_progress', 'answered', 'closed']::text[]
    ),
    (
      'class_inquiries_closed_by_role_check'::text,
      array['closed_by_role', 'parent', 'teacher', 'owner']::text[]
    ),
    (
      'class_inquiries_closed_state_consistency_check'::text,
      array['status', 'closed', 'closed_at', 'closed_by_id', 'closed_by_role']::text[]
    ),
    (
      'class_inquiry_messages_sender_role_check'::text,
      array['sender_role', 'parent', 'teacher', 'owner', 'system']::text[]
    ),
    (
      'class_inquiry_messages_pkey'::text,
      array['id']::text[]
    ),
    (
      'class_inquiry_messages_request_key_key'::text,
      array['request_key']::text[]
    ),
    (
      'class_inquiry_messages_message_type_check'::text,
      array['message_type', 'message', 'status_change']::text[]
    ),
    (
      'class_inquiry_messages_status_pair_check'::text,
      array['status_from', 'status_to', 'is null', 'is not null']::text[]
    ),
    (
      'class_inquiry_messages_status_transition_check'::text,
      array['status_from', 'status_to']::text[]
    ),
    (
      'class_inquiry_messages_status_change_check'::text,
      array['message_type', 'status_change', 'status_from', 'status_to']::text[]
    )
),
expected_foreign_keys(
  constraint_name,
  expected_reference,
  expected_delete_code,
  expected_delete_action
) as (
  values
    ('class_inquiry_daily_counters_center_id_fkey'::text, 'public.centers'::text, 'r'::text, 'RESTRICT'::text),
    ('class_inquiries_class_id_fkey'::text, 'public.classes'::text, 'r'::text, 'RESTRICT'::text),
    ('class_inquiries_center_id_fkey'::text, 'public.centers'::text, 'r'::text, 'RESTRICT'::text),
    ('class_inquiries_author_id_fkey'::text, 'auth.users'::text, 'n'::text, 'SET NULL'::text),
    ('class_inquiries_closed_by_id_fkey'::text, 'auth.users'::text, 'n'::text, 'SET NULL'::text),
    ('class_inquiry_messages_inquiry_id_fkey'::text, 'public.class_inquiries'::text, 'r'::text, 'RESTRICT'::text),
    ('class_inquiry_messages_sender_id_fkey'::text, 'auth.users'::text, 'n'::text, 'SET NULL'::text)
),
expected_indexes(index_name, table_name, required_fragments) as (
  values
    (
      'class_inquiries_author_updated_idx'::text,
      'class_inquiries'::text,
      array['author_id', 'updated_at desc', 'id desc']::text[]
    ),
    (
      'class_inquiries_class_updated_idx'::text,
      'class_inquiries'::text,
      array['class_id', 'updated_at desc', 'id desc']::text[]
    ),
    (
      'class_inquiries_class_status_updated_idx'::text,
      'class_inquiries'::text,
      array['class_id', 'status', 'updated_at desc', 'id desc']::text[]
    ),
    (
      'class_inquiries_class_unanswered_idx'::text,
      'class_inquiries'::text,
      array['class_id', 'updated_at desc', 'id desc', 'received', 'in_progress']::text[]
    ),
    (
      'class_inquiries_class_staff_unread_idx'::text,
      'class_inquiries'::text,
      array['class_id', 'last_parent_message_at desc', 'id desc', 'staff_last_read_at']::text[]
    ),
    (
      'class_inquiries_author_parent_unread_idx'::text,
      'class_inquiries'::text,
      array['author_id', 'last_staff_message_at desc', 'id desc', 'parent_last_read_at']::text[]
    ),
    (
      'class_inquiry_messages_inquiry_created_idx'::text,
      'class_inquiry_messages'::text,
      array['inquiry_id', 'created_at', 'id']::text[]
    )
),
expected_rpcs(signature, expected_result) as (
  values
    (
      'public.create_class_inquiry(uuid,text,text,text,uuid)'::text,
      'TABLE(inquiry_id uuid, document_no text, status text, created_at timestamp with time zone)'::text
    ),
    (
      'public.add_parent_class_inquiry_message(uuid,text,uuid)'::text,
      'TABLE(message_id uuid, inquiry_id uuid, status text, message_created_at timestamp with time zone, last_message_at timestamp with time zone)'::text
    ),
    (
      'public.reply_to_class_inquiry(uuid,text,uuid)'::text,
      'TABLE(message_id uuid, inquiry_id uuid, status text, message_created_at timestamp with time zone, last_message_at timestamp with time zone)'::text
    ),
    (
      'public.start_class_inquiry_review(uuid)'::text,
      'TABLE(inquiry_id uuid, status text, updated_at timestamp with time zone, changed boolean)'::text
    ),
    (
      'public.close_class_inquiry(uuid,uuid)'::text,
      'TABLE(inquiry_id uuid, status text, closed_at timestamp with time zone, closed_by_role text)'::text
    ),
    (
      'public.mark_class_inquiry_parent_read(uuid)'::text,
      'TABLE(inquiry_id uuid, parent_last_read_at timestamp with time zone)'::text
    ),
    (
      'public.mark_class_inquiry_staff_read(uuid)'::text,
      'TABLE(inquiry_id uuid, staff_last_read_at timestamp with time zone)'::text
    ),
    (
      'public.get_my_class_inquiries(uuid,text,boolean,timestamptz,uuid,integer)'::text,
      'TABLE(inquiry_id uuid, document_no text, class_id uuid, category text, subject text, status text, created_at timestamp with time zone, updated_at timestamp with time zone, last_message_at timestamp with time zone, last_staff_message_at timestamp with time zone, parent_last_read_at timestamp with time zone, has_unread_reply boolean, is_closed boolean)'::text
    ),
    (
      'public.get_class_inquiries_for_staff(uuid,text,boolean,boolean,boolean,timestamptz,uuid,integer)'::text,
      'TABLE(inquiry_id uuid, document_no text, class_id uuid, author_id uuid, category text, subject text, status text, created_at timestamp with time zone, updated_at timestamp with time zone, last_message_at timestamp with time zone, last_parent_message_at timestamp with time zone, staff_last_read_at timestamp with time zone, has_unread_parent_message boolean, requires_response boolean, is_closed boolean)'::text
    ),
    (
      'public.get_class_inquiry_thread(uuid)'::text,
      'jsonb'::text
    )
),
expected_policies(table_name, policy_name, required_fragments) as (
  values
    (
      'class_inquiries'::text,
      'class_inquiries_select_participants'::text,
      array['author_id', 'auth.uid', 'is_class_staff', 'class_id']::text[]
    ),
    (
      'class_inquiry_messages'::text,
      'class_inquiry_messages_select_participants'::text,
      array['inquiry_id', 'author_id', 'auth.uid', 'is_class_staff', 'class_id']::text[]
    )
),
expected_authenticated_select(table_name, column_names) as (
  values
    (
      'class_inquiries'::text,
      array[
        'answered_at',
        'author_id',
        'category',
        'class_id',
        'closed_at',
        'closed_by_role',
        'created_at',
        'document_no',
        'id',
        'last_message_at',
        'last_parent_message_at',
        'last_staff_message_at',
        'parent_last_read_at',
        'staff_last_read_at',
        'status',
        'subject',
        'updated_at'
      ]::text[]
    ),
    (
      'class_inquiry_messages'::text,
      array[
        'body',
        'created_at',
        'id',
        'inquiry_id',
        'message_type',
        'sender_id',
        'sender_role',
        'status_from',
        'status_to'
      ]::text[]
    )
),
target_roles(role_name, role_oid) as (
  values
    ('PUBLIC'::text, 0::oid),
    ('anon'::text, pg_catalog.to_regrole('anon')::oid),
    ('authenticated'::text, pg_catalog.to_regrole('authenticated')::oid),
    ('service_role'::text, pg_catalog.to_regrole('service_role')::oid)
),
target_relations as (
  select
    c.oid as relation_oid,
    c.relname,
    c.relowner,
    c.relacl
  from pg_catalog.pg_class as c
  join pg_catalog.pg_namespace as n
    on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in (
      'class_inquiry_daily_counters',
      'class_inquiries',
      'class_inquiry_messages'
    )
),
table_acl_rows as (
  select
    tr.relname,
    acl.grantee,
    acl.privilege_type
  from target_relations as tr
  cross join lateral pg_catalog.aclexplode(tr.relacl) as acl
),
column_acl_rows as (
  select
    tr.relname,
    a.attname,
    acl.grantee,
    acl.privilege_type
  from target_relations as tr
  join pg_catalog.pg_attribute as a
    on a.attrelid = tr.relation_oid
   and a.attnum > 0
   and not a.attisdropped
  cross join lateral pg_catalog.aclexplode(a.attacl) as acl
),
actual_authenticated_select as (
  select
    car.relname as table_name,
    array_agg(car.attname order by car.attname) as column_names
  from column_acl_rows as car
  where car.grantee = pg_catalog.to_regrole('authenticated')::oid
    and car.privilege_type = 'SELECT'
  group by car.relname
),
table_checks as (
  select
    'table_exists:' || et.table_name as check_name,
    pg_catalog.to_regclass('public.' || et.table_name) is not null as passed,
    'relation=' || coalesce(pg_catalog.to_regclass('public.' || et.table_name)::text, 'missing') as details
  from expected_tables as et

  union all

  select
    'rls_enabled:' || et.table_name,
    coalesce(c.relrowsecurity, false),
    'relrowsecurity=' || coalesce(c.relrowsecurity::text, 'missing')
  from expected_tables as et
  left join pg_catalog.pg_class as c
    on c.oid = pg_catalog.to_regclass('public.' || et.table_name)

  union all

  select
    'force_rls_disabled:' || et.table_name,
    c.oid is not null and not c.relforcerowsecurity,
    'relforcerowsecurity=' || coalesce(c.relforcerowsecurity::text, 'missing')
  from expected_tables as et
  left join pg_catalog.pg_class as c
    on c.oid = pg_catalog.to_regclass('public.' || et.table_name)
),
column_checks as (
  select
    'required_columns:' || ec.table_name as check_name,
    count(*) filter (where a.attname is null) = 0 as passed,
    case
      when count(*) filter (where a.attname is null) = 0 then 'all required columns present'
      else 'missing=' || string_agg(required_column, ', ' order by required_column)
        filter (where a.attname is null)
    end as details
  from expected_columns as ec
  cross join lateral unnest(ec.column_names) as required(required_column)
  left join pg_catalog.pg_attribute as a
    on a.attrelid = pg_catalog.to_regclass('public.' || ec.table_name)
   and a.attname = required.required_column
   and a.attnum > 0
   and not a.attisdropped
  group by ec.table_name
),
constraint_checks as (
  select
    'constraint:' || ec.constraint_name as check_name,
    c.oid is not null and c.contype::text = ec.constraint_type as passed,
    coalesce(
      'type=' || c.contype::text || '; definition=' || pg_catalog.pg_get_constraintdef(c.oid),
      'missing'
    ) as details
  from expected_constraints as ec
  left join pg_catalog.pg_constraint as c
    on c.conrelid = pg_catalog.to_regclass('public.' || ec.table_name)
   and c.conname = ec.constraint_name
),
constraint_semantic_checks as (
  select
    'constraint_contract:' || ecs.constraint_name as check_name,
    c.oid is not null
      and not exists (
        select 1
        from unnest(ecs.required_fragments) as fragment(required_fragment)
        where pg_catalog.strpos(
          lower(pg_catalog.pg_get_constraintdef(c.oid)),
          fragment.required_fragment
        ) = 0
      ) as passed,
    coalesce(pg_catalog.pg_get_constraintdef(c.oid), 'missing') as details
  from expected_constraint_semantics as ecs
  left join pg_catalog.pg_constraint as c
    on c.conname = ecs.constraint_name
   and c.connamespace = pg_catalog.to_regnamespace('public')
),
foreign_key_checks as (
  select
    'foreign_key_delete:' || efk.constraint_name as check_name,
    c.oid is not null
      and c.confrelid = pg_catalog.to_regclass(efk.expected_reference)
      and c.confdeltype::text = efk.expected_delete_code as passed,
    'expected_reference=' || efk.expected_reference
      || '; actual_reference=' || coalesce(c.confrelid::regclass::text, 'missing')
      || '; expected_delete=' || efk.expected_delete_action
      || '; actual=' || coalesce(
        case c.confdeltype
          when 'r' then 'RESTRICT'
          when 'n' then 'SET NULL'
          when 'c' then 'CASCADE'
          when 'a' then 'NO ACTION'
          when 'd' then 'SET DEFAULT'
          else c.confdeltype::text
        end,
        'missing'
      )
      || '; definition=' || coalesce(pg_catalog.pg_get_constraintdef(c.oid), 'missing') as details
  from expected_foreign_keys as efk
  left join pg_catalog.pg_constraint as c
    on c.conname = efk.constraint_name
   and c.contype = 'f'
),
index_checks as (
  select
    'index:' || ei.index_name as check_name,
    ic.oid is not null
      and i.indisvalid
      and tc.oid = pg_catalog.to_regclass('public.' || ei.table_name)
      and not exists (
        select 1
        from unnest(ei.required_fragments) as fragment(required_fragment)
        where pg_catalog.strpos(
          lower(pg_catalog.pg_get_indexdef(ic.oid)),
          fragment.required_fragment
        ) = 0
      ) as passed,
    coalesce(pg_catalog.pg_get_indexdef(ic.oid), 'missing')
      || '; predicate=' || coalesce(pg_catalog.pg_get_expr(i.indpred, i.indrelid), 'none') as details
  from expected_indexes as ei
  left join pg_catalog.pg_class as ic
    on ic.relname = ei.index_name
   and ic.relnamespace = pg_catalog.to_regnamespace('public')
  left join pg_catalog.pg_index as i
    on i.indexrelid = ic.oid
  left join pg_catalog.pg_class as tc
    on tc.oid = i.indrelid
),
append_function as (
  select p.*
  from pg_catalog.pg_proc as p
  where p.oid = pg_catalog.to_regprocedure('public.reject_class_inquiry_message_mutation()')
),
append_trigger as (
  select t.*
  from pg_catalog.pg_trigger as t
  where t.tgrelid = pg_catalog.to_regclass('public.class_inquiry_messages')
    and t.tgname = 'class_inquiry_messages_reject_mutation'
    and not t.tgisinternal
),
append_checks as (
  select
    'append_function:exists'::text as check_name,
    exists (select 1 from append_function) as passed,
    'signature=' || coalesce(
      pg_catalog.to_regprocedure('public.reject_class_inquiry_message_mutation()')::text,
      'missing'
    ) as details

  union all

  select
    'append_function:execution_contract',
    coalesce(
      not af.prosecdef
      and af.prorettype = 'trigger'::regtype
      and af.proconfig @> array['search_path=pg_catalog']::text[],
      false
    ),
    coalesce(
      jsonb_build_object(
        'security_definer', af.prosecdef,
        'return_type', pg_catalog.pg_get_function_result(af.oid),
        'config', af.proconfig,
        'owner', pg_catalog.pg_get_userbyid(af.proowner)
      )::text,
      'missing'
    )
  from (select 1) as seed
  left join append_function as af on true

  union all

  select
    'append_function:execute_acl',
    af.oid is not null
      and not exists (
        select 1
        from pg_catalog.aclexplode(af.proacl) as acl
        where acl.grantee = 0
          and acl.privilege_type = 'EXECUTE'
      )
      and not coalesce(pg_catalog.has_function_privilege('anon', af.oid, 'EXECUTE'), false)
      and not coalesce(pg_catalog.has_function_privilege('authenticated', af.oid, 'EXECUTE'), false)
      and not coalesce(pg_catalog.has_function_privilege('service_role', af.oid, 'EXECUTE'), false),
    coalesce(af.proacl::text, 'missing')
  from (select 1) as seed
  left join append_function as af on true

  union all

  select
    'append_trigger:before_update_delete_row',
    coalesce(
      (at.tgtype & 1) = 1
      and (at.tgtype & 2) = 2
      and (at.tgtype & 4) = 0
      and (at.tgtype & 8) = 8
      and (at.tgtype & 16) = 16
      and (at.tgtype & 32) = 0
      and at.tgfoid = pg_catalog.to_regprocedure('public.reject_class_inquiry_message_mutation()'),
      false
    ),
    coalesce(pg_catalog.pg_get_triggerdef(at.oid), 'missing')
  from (select 1) as seed
  left join append_trigger as at on true

  union all

  select
    'append_trigger:enabled',
    coalesce(at.tgenabled = 'O', false),
    'tgenabled=' || coalesce(at.tgenabled::text, 'missing')
  from (select 1) as seed
  left join append_trigger as at on true
),
rpc_catalog as (
  select
    er.signature,
    er.expected_result,
    p.oid,
    p.prosecdef,
    p.proconfig,
    p.proowner,
    p.proacl,
    case when p.oid is null then null else pg_catalog.pg_get_function_result(p.oid) end as actual_result
  from expected_rpcs as er
  left join pg_catalog.pg_proc as p
    on p.oid = pg_catalog.to_regprocedure(er.signature)
),
rpc_checks as (
  select
    'rpc:' || rc.signature as check_name,
    coalesce(
      rc.oid is not null
        and rc.prosecdef
        and rc.proconfig @> array['search_path=pg_catalog, public, auth']::text[]
        and rc.actual_result = rc.expected_result
        and coalesce(pg_catalog.has_function_privilege('authenticated', rc.oid, 'EXECUTE'), false)
        and not coalesce(pg_catalog.has_function_privilege('anon', rc.oid, 'EXECUTE'), false)
        and not coalesce(pg_catalog.has_function_privilege('service_role', rc.oid, 'EXECUTE'), false)
        and not exists (
          select 1
          from pg_catalog.aclexplode(rc.proacl) as acl
          where acl.grantee = 0
            and acl.privilege_type = 'EXECUTE'
        ),
      false
    ) as passed,
    coalesce(
      jsonb_build_object(
        'exists', rc.oid is not null,
        'security_definer', rc.prosecdef,
        'search_path', rc.proconfig,
        'owner', pg_catalog.pg_get_userbyid(rc.proowner),
        'execute_acl', rc.proacl,
        'return_type', rc.actual_result,
        'expected_return_type', rc.expected_result
      )::text,
      'missing'
    ) as details
  from rpc_catalog as rc
),
policy_checks as (
  select
    'policy:' || ep.policy_name as check_name,
    p.oid is not null
      and p.polcmd = 'r'
      and p.polqual is not null
      and array_length(p.polroles, 1) = 1
      and pg_catalog.to_regrole('authenticated')::oid = any(p.polroles)
      and not exists (
        select 1
        from unnest(ep.required_fragments) as fragment(required_fragment)
        where pg_catalog.strpos(
          lower(pg_catalog.pg_get_expr(p.polqual, p.polrelid)),
          fragment.required_fragment
        ) = 0
      ) as passed,
    coalesce(
      jsonb_build_object(
        'command', p.polcmd,
        'roles', p.polroles,
        'qual', pg_catalog.pg_get_expr(p.polqual, p.polrelid),
        'with_check', pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid)
      )::text,
      'missing'
    ) as details
  from expected_policies as ep
  left join pg_catalog.pg_policy as p
    on p.polrelid = pg_catalog.to_regclass('public.' || ep.table_name)
   and p.polname = ep.policy_name

  union all

  select
    'policy:no_insert_update_delete',
    not exists (
      select 1
      from pg_catalog.pg_policy as p
      where p.polrelid in (
        pg_catalog.to_regclass('public.class_inquiry_daily_counters'),
        pg_catalog.to_regclass('public.class_inquiries'),
        pg_catalog.to_regclass('public.class_inquiry_messages')
      )
        and p.polcmd in ('a', 'w', 'd', '*')
    ),
    'non_select_policy_count=' || (
      select count(*)::text
      from pg_catalog.pg_policy as p
      where p.polrelid in (
        pg_catalog.to_regclass('public.class_inquiry_daily_counters'),
        pg_catalog.to_regclass('public.class_inquiries'),
        pg_catalog.to_regclass('public.class_inquiry_messages')
      )
        and p.polcmd in ('a', 'w', 'd', '*')
    )
),
privilege_checks as (
  select
    'privilege:no_target_role_table_acl'::text as check_name,
    not exists (
      select 1
      from table_acl_rows as tar
      join target_roles as tr
        on tr.role_oid = tar.grantee
    ) as passed,
    'direct table ACL rows for PUBLIC/anon/authenticated/service_role=' || (
      select count(*)::text
      from table_acl_rows as tar
      join target_roles as tr
        on tr.role_oid = tar.grantee
    ) as details

  union all

  select
    'privilege:counter_no_column_acl',
    not exists (
      select 1
      from column_acl_rows as car
      join target_roles as tr
        on tr.role_oid = car.grantee
      where car.relname = 'class_inquiry_daily_counters'
    ),
    'target-role column ACL rows=' || (
      select count(*)::text
      from column_acl_rows as car
      join target_roles as tr
        on tr.role_oid = car.grantee
      where car.relname = 'class_inquiry_daily_counters'
    )

  union all

  select
    'privilege:authenticated_inquiries_select_columns',
    coalesce(aas.column_names::text[] = eas.column_names::text[], false),
    'expected=' || eas.column_names::text
      || '; actual=' || coalesce(aas.column_names::text, '{}')
  from expected_authenticated_select as eas
  left join actual_authenticated_select as aas
    on aas.table_name = eas.table_name
  where eas.table_name = 'class_inquiries'

  union all

  select
    'privilege:authenticated_messages_select_columns',
    coalesce(aas.column_names::text[] = eas.column_names::text[], false),
    'expected=' || eas.column_names::text
      || '; actual=' || coalesce(aas.column_names::text, '{}')
  from expected_authenticated_select as eas
  left join actual_authenticated_select as aas
    on aas.table_name = eas.table_name
  where eas.table_name = 'class_inquiry_messages'

  union all

  select
    'privilege:public_anon_service_no_column_acl',
    not exists (
      select 1
      from column_acl_rows as car
      join target_roles as tr
        on tr.role_oid = car.grantee
      where tr.role_name in ('PUBLIC', 'anon', 'service_role')
    ),
    'prohibited column ACL rows=' || (
      select count(*)::text
      from column_acl_rows as car
      join target_roles as tr
        on tr.role_oid = car.grantee
      where tr.role_name in ('PUBLIC', 'anon', 'service_role')
    )

  union all

  select
    'privilege:authenticated_no_column_mutation',
    not exists (
      select 1
      from column_acl_rows as car
      where car.grantee = pg_catalog.to_regrole('authenticated')::oid
        and car.privilege_type in ('INSERT', 'UPDATE', 'REFERENCES')
    ),
    'authenticated mutation/reference column ACL rows=' || (
      select count(*)::text
      from column_acl_rows as car
      where car.grantee = pg_catalog.to_regrole('authenticated')::oid
        and car.privilege_type in ('INSERT', 'UPDATE', 'REFERENCES')
    )
),
legacy_checks as (
  select
    'legacy:class_comments_exists'::text as check_name,
    pg_catalog.to_regclass('public.class_comments') is not null as passed,
    coalesce(
      (
        select 'catalog_estimated_rows=' || c.reltuples::bigint::text
        from pg_catalog.pg_class as c
        where c.oid = pg_catalog.to_regclass('public.class_comments')
      ),
      'missing'
    ) as details
),
checks as (
  select * from table_checks
  union all select * from column_checks
  union all select * from constraint_checks
  union all select * from constraint_semantic_checks
  union all select * from foreign_key_checks
  union all select * from index_checks
  union all select * from append_checks
  union all select * from rpc_checks
  union all select * from policy_checks
  union all select * from privilege_checks
  union all select * from legacy_checks
),
report_rows as (
  select
    0 as summary_order,
    c.check_name,
    c.passed,
    c.details
  from checks as c

  union all

  select
    1,
    'SUMMARY',
    coalesce(bool_and(coalesce(c.passed, false)), false),
    format(
      'passed=%s; failed=%s; total=%s',
      count(*) filter (where coalesce(c.passed, false)),
      count(*) filter (where not coalesce(c.passed, false)),
      count(*)
    )
  from checks as c
)
select
  rr.check_name,
  rr.passed,
  rr.details
from report_rows as rr
order by
  rr.summary_order,
  coalesce(rr.passed, false),
  rr.check_name;
