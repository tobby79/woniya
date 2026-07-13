-- Baseline manually-created bus schedule schema and admission deadline fields.
-- Also tightens bus table grants and RLS so draft center routes are not public.

create table if not exists public.bus_routes (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null
    constraint bus_routes_center_id_fkey references public.centers(id) on delete cascade,
  route_name text not null,
  route_color text,
  sort integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_bus_routes_center
  on public.bus_routes (center_id);

create table if not exists public.bus_stops (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null
    constraint bus_stops_route_id_fkey references public.bus_routes(id) on delete cascade,
  stop_name text not null,
  pickup_time time,
  dropoff_time time,
  sort integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_bus_stops_route
  on public.bus_stops (route_id);

alter table public.admissions
  add column if not exists deadline_date date;

alter table public.template_admissions
  add column if not exists deadline_date date;

alter table public.bus_routes enable row level security;
alter table public.bus_stops enable row level security;

revoke all on table public.bus_routes from public;
revoke all on table public.bus_stops from public;

revoke truncate, trigger, references on table public.bus_routes from public, anon, authenticated;
revoke truncate, trigger, references on table public.bus_stops from public, anon, authenticated;

revoke insert, update, delete, truncate on table public.bus_routes from anon;
revoke insert, update, delete, truncate on table public.bus_stops from anon;

grant select on table public.bus_routes to anon;
grant select on table public.bus_stops to anon;

grant select, insert, update, delete on table public.bus_routes to authenticated;
grant select, insert, update, delete on table public.bus_stops to authenticated;

drop policy if exists "bus_routes public read" on public.bus_routes;
drop policy if exists "bus_routes owner write" on public.bus_routes;
drop policy if exists "bus_routes_public_select_published" on public.bus_routes;
drop policy if exists "bus_routes_owner_select" on public.bus_routes;
drop policy if exists "bus_routes_owner_insert" on public.bus_routes;
drop policy if exists "bus_routes_owner_update" on public.bus_routes;
drop policy if exists "bus_routes_owner_delete" on public.bus_routes;

create policy "bus_routes_public_select_published"
on public.bus_routes
for select
to anon, authenticated
using (
  exists (
    select 1
    from public.centers c
    where c.id = bus_routes.center_id
      and c.status = 'published'
  )
);

create policy "bus_routes_owner_select"
on public.bus_routes
for select
to authenticated
using (
  exists (
    select 1
    from public.centers c
    where c.id = bus_routes.center_id
      and c.owner_id = auth.uid()
  )
);

create policy "bus_routes_owner_insert"
on public.bus_routes
for insert
to authenticated
with check (
  exists (
    select 1
    from public.centers c
    where c.id = bus_routes.center_id
      and c.owner_id = auth.uid()
  )
);

create policy "bus_routes_owner_update"
on public.bus_routes
for update
to authenticated
using (
  exists (
    select 1
    from public.centers c
    where c.id = bus_routes.center_id
      and c.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.centers c
    where c.id = bus_routes.center_id
      and c.owner_id = auth.uid()
  )
);

create policy "bus_routes_owner_delete"
on public.bus_routes
for delete
to authenticated
using (
  exists (
    select 1
    from public.centers c
    where c.id = bus_routes.center_id
      and c.owner_id = auth.uid()
  )
);

drop policy if exists "bus_stops public read" on public.bus_stops;
drop policy if exists "bus_stops owner write" on public.bus_stops;
drop policy if exists "bus_stops_public_select_published" on public.bus_stops;
drop policy if exists "bus_stops_owner_select" on public.bus_stops;
drop policy if exists "bus_stops_owner_insert" on public.bus_stops;
drop policy if exists "bus_stops_owner_update" on public.bus_stops;
drop policy if exists "bus_stops_owner_delete" on public.bus_stops;

create policy "bus_stops_public_select_published"
on public.bus_stops
for select
to anon, authenticated
using (
  exists (
    select 1
    from public.bus_routes br
    join public.centers c on c.id = br.center_id
    where br.id = bus_stops.route_id
      and c.status = 'published'
  )
);

create policy "bus_stops_owner_select"
on public.bus_stops
for select
to authenticated
using (
  exists (
    select 1
    from public.bus_routes br
    join public.centers c on c.id = br.center_id
    where br.id = bus_stops.route_id
      and c.owner_id = auth.uid()
  )
);

create policy "bus_stops_owner_insert"
on public.bus_stops
for insert
to authenticated
with check (
  exists (
    select 1
    from public.bus_routes br
    join public.centers c on c.id = br.center_id
    where br.id = bus_stops.route_id
      and c.owner_id = auth.uid()
  )
);

create policy "bus_stops_owner_update"
on public.bus_stops
for update
to authenticated
using (
  exists (
    select 1
    from public.bus_routes br
    join public.centers c on c.id = br.center_id
    where br.id = bus_stops.route_id
      and c.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.bus_routes br
    join public.centers c on c.id = br.center_id
    where br.id = bus_stops.route_id
      and c.owner_id = auth.uid()
  )
);

create policy "bus_stops_owner_delete"
on public.bus_stops
for delete
to authenticated
using (
  exists (
    select 1
    from public.bus_routes br
    join public.centers c on c.id = br.center_id
    where br.id = bus_stops.route_id
      and c.owner_id = auth.uid()
  )
);
