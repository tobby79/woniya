-- ===== 014_class_mini_homepage.sql =====

alter table classes add column if not exists teacher_id uuid references auth.users(id);

-- 1. 테이블 생성

create table if not exists class_invites (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references classes(id) on delete cascade,
  code text unique not null,
  expires_at timestamptz,
  status text not null default 'active' check (status in ('active','expired','revoked')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists class_enrollments (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references classes(id) on delete cascade,
  parent_id uuid not null references auth.users(id) on delete cascade,
  invite_id uuid references class_invites(id),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  requested_at timestamptz not null default now(),
  approved_at timestamptz,
  approved_by uuid references auth.users(id),
  unique (class_id, parent_id)
);

create table if not exists class_mini (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null unique references classes(id) on delete cascade,
  cover_image text,
  theme_color text,
  intro text,
  teacher_message text,
  modules_enabled jsonb not null default '{"diary":true,"album":true,"guestbook":true,"notice":true,"letters":true}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists class_posts (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references classes(id) on delete cascade,
  type text not null check (type in ('diary','notice')),
  title text,
  body text,
  created_at timestamptz not null default now()
);

create table if not exists class_media (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references classes(id) on delete cascade,
  post_id uuid references class_posts(id) on delete set null,
  url text not null,
  caption text,
  taken_at date,
  uploaded_at timestamptz not null default now()
);

create table if not exists class_comments (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references classes(id) on delete cascade,
  author_id uuid not null references auth.users(id),
  body text not null,
  created_at timestamptz not null default now(),
  reply text,
  replied_at timestamptz
);

-- 2. 권한 판별 헬퍼 함수

create or replace function is_class_teacher(p_class_id uuid) returns boolean
language sql security definer stable as $$
  select exists (
    select 1 from classes where id = p_class_id and teacher_id = auth.uid()
  );
$$;

create or replace function is_class_owner(p_class_id uuid) returns boolean
language sql security definer stable as $$
  select exists (
    select 1 from classes c
    join centers ct on ct.id = c.center_id
    where c.id = p_class_id and ct.owner_id = auth.uid()
  );
$$;

create or replace function is_class_staff(p_class_id uuid) returns boolean
language sql security definer stable as $$
  select is_class_teacher(p_class_id) or is_class_owner(p_class_id);
$$;

create or replace function is_approved_parent(p_class_id uuid) returns boolean
language sql security definer stable as $$
  select exists (
    select 1 from class_enrollments
    where class_id = p_class_id and parent_id = auth.uid() and status = 'approved'
  );
$$;

-- 3. 초대 코드 검증 + 신청 등록 RPC (학부모가 class_invites 테이블에 직접 접근하지 않도록)

create or replace function redeem_class_invite(p_code text) returns uuid
language plpgsql security definer as $$
declare
  v_invite class_invites%rowtype;
  v_enrollment_id uuid;
begin
  select * into v_invite from class_invites
  where code = p_code and status = 'active' and (expires_at is null or expires_at > now());

  if not found then
    raise exception '유효하지 않거나 만료된 초대 코드입니다';
  end if;

  insert into class_enrollments (class_id, parent_id, invite_id, status)
  values (v_invite.class_id, auth.uid(), v_invite.id, 'pending')
  on conflict (class_id, parent_id) do nothing
  returning id into v_enrollment_id;

  if v_enrollment_id is null then
    select id into v_enrollment_id from class_enrollments
    where class_id = v_invite.class_id and parent_id = auth.uid();
  end if;

  return v_enrollment_id;
end;
$$;

grant execute on function redeem_class_invite(text) to authenticated;

-- 4. RLS 활성화

alter table class_invites enable row level security;
alter table class_enrollments enable row level security;
alter table class_mini enable row level security;
alter table class_posts enable row level security;
alter table class_media enable row level security;
alter table class_comments enable row level security;

-- 5. GRANT (테이블 레벨 접근 권한 — RLS와 별개로 반드시 필요, 과거 42501 오류 재발 방지)

grant select, insert, update, delete on class_invites to authenticated;
grant select, insert, update, delete on class_enrollments to authenticated;
grant select, insert, update on class_mini to authenticated;
grant select, insert, update, delete on class_posts to authenticated;
grant select, insert, update, delete on class_media to authenticated;
grant select, insert, update on class_comments to authenticated;

-- 6. RLS 정책 — class_invites (원장·담임 교사만 접근, 학부모는 RPC로만)

create policy class_invites_staff_select on class_invites
  for select using (is_class_staff(class_id));

create policy class_invites_staff_insert on class_invites
  for insert with check (is_class_staff(class_id));

create policy class_invites_staff_update on class_invites
  for update using (is_class_staff(class_id));

create policy class_invites_staff_delete on class_invites
  for delete using (is_class_staff(class_id));

-- 7. RLS 정책 — class_enrollments

create policy class_enrollments_select on class_enrollments
  for select using (parent_id = auth.uid() or is_class_staff(class_id));

create policy class_enrollments_parent_insert on class_enrollments
  for insert with check (parent_id = auth.uid());

create policy class_enrollments_staff_update on class_enrollments
  for update using (is_class_staff(class_id));

-- 8. RLS 정책 — class_mini (조회는 스태프+승인학부모, 관리는 담임 교사만)

create policy class_mini_select on class_mini
  for select using (is_class_staff(class_id) or is_approved_parent(class_id));

create policy class_mini_teacher_insert on class_mini
  for insert with check (is_class_teacher(class_id));

create policy class_mini_teacher_update on class_mini
  for update using (is_class_teacher(class_id));

-- 9. RLS 정책 — class_posts (담임 교사만 작성, 스태프+승인학부모 열람)

create policy class_posts_select on class_posts
  for select using (is_class_staff(class_id) or is_approved_parent(class_id));

create policy class_posts_teacher_insert on class_posts
  for insert with check (is_class_teacher(class_id));

create policy class_posts_teacher_update on class_posts
  for update using (is_class_teacher(class_id));

create policy class_posts_teacher_delete on class_posts
  for delete using (is_class_teacher(class_id));

-- 10. RLS 정책 — class_media (담임 교사만 업로드, 스태프+승인학부모 열람)

create policy class_media_select on class_media
  for select using (is_class_staff(class_id) or is_approved_parent(class_id));

create policy class_media_teacher_insert on class_media
  for insert with check (is_class_teacher(class_id));

create policy class_media_teacher_update on class_media
  for update using (is_class_teacher(class_id));

create policy class_media_teacher_delete on class_media
  for delete using (is_class_teacher(class_id));

-- 11. RLS 정책 — class_comments (승인 학부모 작성, 담임 교사 답글, 스태프+승인학부모 열람)

create policy class_comments_select on class_comments
  for select using (is_class_staff(class_id) or is_approved_parent(class_id));

create policy class_comments_parent_insert on class_comments
  for insert with check (is_approved_parent(class_id) and author_id = auth.uid());

create policy class_comments_teacher_update on class_comments
  for update using (is_class_teacher(class_id));

-- ===== 마이그레이션 끝 =====
