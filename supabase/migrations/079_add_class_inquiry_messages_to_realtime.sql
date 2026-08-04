-- Register inquiry message inserts with Supabase Realtime.
-- Scope: publication membership for public.class_inquiry_messages only.

begin;

do $migration$
begin
  if not exists (
    select 1
    from pg_catalog.pg_publication
    where pubname = 'supabase_realtime'
  ) then
    raise exception using
      errcode = '42704',
      message = 'Required publication "supabase_realtime" does not exist.';
  end if;

  if to_regclass('public.class_inquiry_messages') is null then
    raise exception using
      errcode = '42P01',
      message = 'Required table "public.class_inquiry_messages" does not exist.';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'class_inquiry_messages'
  ) then
    alter publication supabase_realtime
      add table public.class_inquiry_messages;
  end if;
end
$migration$;

commit;
