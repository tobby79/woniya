-- Center review links for pre-publish director review.
-- Raw review tokens are returned once to the browser and are never stored.

create extension if not exists pgcrypto;

create table if not exists public.center_review_links (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.centers(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz,
  revoked_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  last_accessed_at timestamptz
);

create index if not exists center_review_links_center_id_idx
  on public.center_review_links (center_id, created_at desc);

create index if not exists center_review_links_active_idx
  on public.center_review_links (center_id, expires_at)
  where revoked_at is null;

alter table public.center_review_links enable row level security;

revoke all on table public.center_review_links from public;
revoke all on table public.center_review_links from anon;
revoke all on table public.center_review_links from authenticated;

grant select, insert, update, delete on table public.center_review_links to service_role;

drop policy if exists center_review_links_admin_select on public.center_review_links;
create policy center_review_links_admin_select
  on public.center_review_links
  for select
  to authenticated
  using (auth.email() = 'tobby79@naver.com');

drop policy if exists center_review_links_admin_insert on public.center_review_links;
create policy center_review_links_admin_insert
  on public.center_review_links
  for insert
  to authenticated
  with check (auth.email() = 'tobby79@naver.com');

drop policy if exists center_review_links_admin_update on public.center_review_links;
create policy center_review_links_admin_update
  on public.center_review_links
  for update
  to authenticated
  using (auth.email() = 'tobby79@naver.com')
  with check (auth.email() = 'tobby79@naver.com');

create or replace function public.create_center_review_link(p_center_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_email text;
  v_center record;
  v_token text;
  v_token_hash text;
  v_link_id uuid;
  v_expires_at timestamptz;
begin
  v_admin_email := auth.email();
  if v_admin_email is null or lower(v_admin_email) <> 'tobby79@naver.com' then
    raise exception 'platform admin only';
  end if;

  if p_center_id is null then
    raise exception 'center_id is required';
  end if;

  select id, template
    into v_center
    from public.centers
    where id = p_center_id;

  if not found then
    raise exception 'center not found';
  end if;

  update public.center_review_links
    set revoked_at = now()
    where center_id = p_center_id
      and revoked_at is null
      and (expires_at is null or expires_at > now());

  v_token := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');
  v_expires_at := now() + interval '14 days';

  insert into public.center_review_links (
    center_id,
    token_hash,
    expires_at,
    created_by
  )
  values (
    p_center_id,
    v_token_hash,
    v_expires_at,
    auth.uid()
  )
  returning id into v_link_id;

  return jsonb_build_object(
    'link_id', v_link_id,
    'center_id', p_center_id,
    'template', v_center.template,
    'token', v_token,
    'expires_at', v_expires_at
  );
end;
$$;

create or replace function public.revoke_center_review_link(p_link_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_email text;
  v_link record;
begin
  v_admin_email := auth.email();
  if v_admin_email is null or lower(v_admin_email) <> 'tobby79@naver.com' then
    raise exception 'platform admin only';
  end if;

  if p_link_id is null then
    raise exception 'link_id is required';
  end if;

  update public.center_review_links
    set revoked_at = now()
    where id = p_link_id
    returning id, center_id, revoked_at into v_link;

  if not found then
    raise exception 'review link not found';
  end if;

  return jsonb_build_object(
    'link_id', v_link.id,
    'center_id', v_link.center_id,
    'revoked_at', v_link.revoked_at
  );
end;
$$;

create or replace function public.get_center_by_review_token(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
  v_token_hash text;
  v_link record;
  v_center public.centers%rowtype;
  v_media jsonb;
  v_admissions jsonb;
  v_row jsonb;
begin
  v_token := trim(coalesce(p_token, ''));
  if v_token = '' then
    return null;
  end if;

  v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

  select *
    into v_link
    from public.center_review_links
    where token_hash = v_token_hash
      and revoked_at is null
      and (expires_at is null or expires_at > now())
    limit 1;

  if not found then
    return null;
  end if;

  update public.center_review_links
    set last_accessed_at = now()
    where id = v_link.id;

  select *
    into v_center
    from public.centers
    where id = v_link.center_id;

  if not found then
    return null;
  end if;

  select coalesce(jsonb_agg(to_jsonb(cm) order by cm.sort_order), '[]'::jsonb)
    into v_media
    from public.center_media cm
    where cm.center_id = v_center.id;

  select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb)
    into v_admissions
    from public.admissions a
    where a.center_id = v_center.id;

  v_row := (to_jsonb(v_center) - 'owner_id') || jsonb_build_object(
    'center_media', v_media,
    'admissions', v_admissions,
    'review_link_id', v_link.id,
    'review_expires_at', v_link.expires_at
  );

  return v_row;
end;
$$;

revoke all on function public.create_center_review_link(uuid) from public;
revoke all on function public.create_center_review_link(uuid) from anon;
grant execute on function public.create_center_review_link(uuid) to authenticated;

revoke all on function public.revoke_center_review_link(uuid) from public;
revoke all on function public.revoke_center_review_link(uuid) from anon;
grant execute on function public.revoke_center_review_link(uuid) to authenticated;

revoke all on function public.get_center_by_review_token(text) from public;
grant execute on function public.get_center_by_review_token(text) to anon, authenticated;
