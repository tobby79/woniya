-- ===== 017_service_role_grants.sql =====

grant select, insert, update, delete on teacher_invites to service_role;
grant select, insert, update, delete on class_invites to service_role;
grant select, insert, update, delete on class_enrollments to service_role;
grant select, insert, update, delete on class_mini to service_role;
grant select, insert, update, delete on class_posts to service_role;
grant select, insert, update, delete on class_media to service_role;
grant select, insert, update, delete on class_comments to service_role;

-- ===== 끝 =====
