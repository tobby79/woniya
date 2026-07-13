revoke truncate, trigger, references on table
  public.admissions,
  public.center_applications,
  public.center_media,
  public.centers,
  public.class_comments,
  public.class_enrollments,
  public.class_invites,
  public.class_media,
  public.class_mini,
  public.class_posts,
  public.classes,
  public.teacher_invites
from public, anon, authenticated;
