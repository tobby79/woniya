begin;

drop policy if exists class_posts_teacher_insert on public.class_posts;
drop policy if exists class_posts_teacher_update on public.class_posts;
drop policy if exists class_posts_teacher_delete on public.class_posts;

create policy class_posts_staff_insert
  on public.class_posts
  for insert
  to authenticated
  with check (public.is_class_staff(class_id));

create policy class_posts_staff_update
  on public.class_posts
  for update
  to authenticated
  using (public.is_class_staff(class_id))
  with check (public.is_class_staff(class_id));

create policy class_posts_staff_delete
  on public.class_posts
  for delete
  to authenticated
  using (public.is_class_staff(class_id));

drop policy if exists class_media_teacher_insert on public.class_media;
drop policy if exists class_media_teacher_update on public.class_media;
drop policy if exists class_media_teacher_delete on public.class_media;

create policy class_media_staff_insert
  on public.class_media
  for insert
  to authenticated
  with check (
    public.is_class_staff(class_id)
    and (
      post_id is null
      or exists (
        select 1
        from public.class_posts as cp
        where cp.id = class_media.post_id
          and cp.class_id = class_media.class_id
      )
    )
  );

create policy class_media_staff_update
  on public.class_media
  for update
  to authenticated
  using (public.is_class_staff(class_id))
  with check (
    public.is_class_staff(class_id)
    and (
      post_id is null
      or exists (
        select 1
        from public.class_posts as cp
        where cp.id = class_media.post_id
          and cp.class_id = class_media.class_id
      )
    )
  );

create policy class_media_staff_delete
  on public.class_media
  for delete
  to authenticated
  using (public.is_class_staff(class_id));

drop policy if exists class_comments_teacher_update on public.class_comments;

create policy class_comments_staff_update
  on public.class_comments
  for update
  to authenticated
  using (public.is_class_staff(class_id))
  with check (public.is_class_staff(class_id));

commit;
