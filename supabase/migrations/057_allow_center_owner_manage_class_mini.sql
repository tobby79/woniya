-- Allow both the assigned class teacher and the owning center director to
-- create and update the initial class mini homepage row.

drop policy if exists class_mini_teacher_insert on public.class_mini;
drop policy if exists class_mini_teacher_update on public.class_mini;
drop policy if exists class_mini_staff_insert on public.class_mini;
drop policy if exists class_mini_staff_update on public.class_mini;

create policy class_mini_staff_insert
  on public.class_mini
  for insert
  to authenticated
  with check (public.is_class_staff(class_id));

create policy class_mini_staff_update
  on public.class_mini
  for update
  to authenticated
  using (public.is_class_staff(class_id))
  with check (public.is_class_staff(class_id));
