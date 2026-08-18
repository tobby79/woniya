begin;

-- resolved_at is the retention clock for completed application personal data.
-- Existing terminal rows are not backfilled because their historical resolution
-- time cannot be reconstructed reliably. Cleanup belongs in a later migration.
alter table public.center_applications
  add column if not exists resolved_at timestamptz;

comment on column public.center_applications.resolved_at is
  'Time the application first entered done or rejected; used for personal-data retention. Legacy terminal rows may remain NULL when the historical resolution time is unknown.';

create or replace function public.set_center_application_resolved_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_old_terminal boolean;
  v_new_terminal boolean;
begin
  v_new_terminal := new.status in ('done', 'rejected');

  if tg_op = 'INSERT' then
    if new.resolved_at is not null then
      raise exception 'center_applications.resolved_at is managed by the database';
    end if;

    if v_new_terminal then
      new.resolved_at := now();
    else
      new.resolved_at := null;
    end if;

    return new;
  end if;

  v_old_terminal := old.status in ('done', 'rejected');

  if new.resolved_at is distinct from old.resolved_at then
    raise exception 'center_applications.resolved_at is managed by the database';
  end if;

  if v_old_terminal and not v_new_terminal then
    raise exception 'resolved center applications cannot return to a nonterminal status';
  end if;

  if not v_old_terminal and v_new_terminal then
    if old.resolved_at is not null then
      raise exception 'nonterminal center applications cannot have resolved_at';
    end if;
    new.resolved_at := now();
  else
    -- Preserve the first resolution time, including an unknown legacy NULL.
    new.resolved_at := old.resolved_at;
  end if;

  return new;
end;
$$;

drop trigger if exists center_applications_set_resolved_at
  on public.center_applications;

create trigger center_applications_set_resolved_at
  before insert or update of status, resolved_at
  on public.center_applications
  for each row
  execute function public.set_center_application_resolved_at();

alter table public.center_applications
  add constraint center_applications_resolved_at_status_check
  check (resolved_at is null or status in ('done', 'rejected'));

commit;
