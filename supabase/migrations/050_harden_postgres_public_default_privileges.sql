alter default privileges for role postgres in schema public
  revoke maintain, truncate, trigger, references on tables
  from public, anon, authenticated;
