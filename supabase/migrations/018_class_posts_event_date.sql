-- ===== 018_class_posts_event_date.sql =====

alter table public.class_posts
  add column if not exists event_date date;

alter table public.class_posts
  drop constraint if exists class_posts_type_check;

alter table public.class_posts
  add constraint class_posts_type_check
  check (type in ('diary', 'notice', 'event', 'album'));

-- Let assigned teachers discover their own class even when the center is not public.
drop policy if exists classes_teacher_select on public.classes;
create policy classes_teacher_select on public.classes
  for select
  to authenticated
  using (teacher_id = auth.uid());

-- Keep class post writes scoped to the authenticated teacher assigned to the class.
drop policy if exists class_posts_teacher_insert on public.class_posts;
drop policy if exists class_posts_teacher_update on public.class_posts;
drop policy if exists class_posts_teacher_delete on public.class_posts;

create policy class_posts_teacher_insert on public.class_posts
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.classes c
      where c.id = class_posts.class_id
        and c.teacher_id = auth.uid()
    )
  );

create policy class_posts_teacher_update on public.class_posts
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.classes c
      where c.id = class_posts.class_id
        and c.teacher_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.classes c
      where c.id = class_posts.class_id
        and c.teacher_id = auth.uid()
    )
  );

create policy class_posts_teacher_delete on public.class_posts
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.classes c
      where c.id = class_posts.class_id
        and c.teacher_id = auth.uid()
    )
  );

-- Keep class media writes scoped to the authenticated teacher assigned to the class.
drop policy if exists class_media_teacher_insert on public.class_media;
drop policy if exists class_media_teacher_update on public.class_media;
drop policy if exists class_media_teacher_delete on public.class_media;

create policy class_media_teacher_insert on public.class_media
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.classes c
      where c.id = class_media.class_id
        and c.teacher_id = auth.uid()
    )
  );

create policy class_media_teacher_update on public.class_media
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.classes c
      where c.id = class_media.class_id
        and c.teacher_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.classes c
      where c.id = class_media.class_id
        and c.teacher_id = auth.uid()
    )
  );

create policy class_media_teacher_delete on public.class_media
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.classes c
      where c.id = class_media.class_id
        and c.teacher_id = auth.uid()
    )
  );

-- Parents may create guestbook entries, but replies remain teacher-only.
drop policy if exists class_comments_parent_insert on public.class_comments;
drop policy if exists class_comments_teacher_update on public.class_comments;

create policy class_comments_parent_insert on public.class_comments
  for insert
  to authenticated
  with check (
    is_approved_parent(class_id)
    and author_id = auth.uid()
    and reply is null
    and replied_at is null
  );

create policy class_comments_teacher_update on public.class_comments
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.classes c
      where c.id = class_comments.class_id
        and c.teacher_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.classes c
      where c.id = class_comments.class_id
        and c.teacher_id = auth.uid()
    )
  );

-- Column grants make teacher replies the only authenticated UPDATE surface.
revoke insert, update on public.class_comments from authenticated;
grant select on public.class_comments to authenticated;
grant insert (class_id, author_id, body) on public.class_comments to authenticated;
grant update (reply, replied_at) on public.class_comments to authenticated;

grant select, insert, update, delete on public.class_posts to authenticated;
grant select, insert, update, delete on public.class_media to authenticated;

-- ===== 끝 =====
