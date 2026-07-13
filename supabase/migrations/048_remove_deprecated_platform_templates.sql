-- Remove the deprecated platform_templates table after template_centers
-- canonicalization has had a chance to copy every legacy template row.
-- Keep template-previews storage and the canonical template_* tables intact.

do $$
declare
  missing_legacy_templates integer;
begin
  if to_regclass('public.platform_templates') is null then
    return;
  end if;

  if to_regclass('public.template_centers') is null then
    raise exception
      'Cannot drop public.platform_templates: public.template_centers does not exist.';
  end if;

  select count(*)
    into missing_legacy_templates
  from public.platform_templates pt
  where not exists (
    select 1
    from public.template_centers tc
    where tc.template_id = pt.template_id
  );

  if missing_legacy_templates > 0 then
    raise exception
      'Cannot drop public.platform_templates: % legacy template rows are not present in public.template_centers.',
      missing_legacy_templates;
  end if;

  drop table public.platform_templates;
end $$;
