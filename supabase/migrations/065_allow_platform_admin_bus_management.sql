-- Allow the platform administrator to manage bus routes and stops for real
-- centers, including draft centers that do not have an owner yet.

begin;

-- Keep these policies separate from the existing published-read and owner
-- policies so those access rules continue to be evaluated independently.
drop policy if exists bus_routes_platform_admin_select on public.bus_routes;
create policy bus_routes_platform_admin_select
  on public.bus_routes
  for select
  to authenticated
  using (auth.email() = 'tobby79@naver.com');

drop policy if exists bus_routes_platform_admin_insert on public.bus_routes;
create policy bus_routes_platform_admin_insert
  on public.bus_routes
  for insert
  to authenticated
  with check (
    auth.email() = 'tobby79@naver.com'
    and exists (
      select 1
      from public.centers c
      where c.id = bus_routes.center_id
    )
  );

drop policy if exists bus_routes_platform_admin_update on public.bus_routes;
create policy bus_routes_platform_admin_update
  on public.bus_routes
  for update
  to authenticated
  using (auth.email() = 'tobby79@naver.com')
  with check (
    auth.email() = 'tobby79@naver.com'
    and exists (
      select 1
      from public.centers c
      where c.id = bus_routes.center_id
    )
  );

drop policy if exists bus_routes_platform_admin_delete on public.bus_routes;
create policy bus_routes_platform_admin_delete
  on public.bus_routes
  for delete
  to authenticated
  using (auth.email() = 'tobby79@naver.com');

drop policy if exists bus_stops_platform_admin_select on public.bus_stops;
create policy bus_stops_platform_admin_select
  on public.bus_stops
  for select
  to authenticated
  using (auth.email() = 'tobby79@naver.com');

drop policy if exists bus_stops_platform_admin_insert on public.bus_stops;
create policy bus_stops_platform_admin_insert
  on public.bus_stops
  for insert
  to authenticated
  with check (
    auth.email() = 'tobby79@naver.com'
    and exists (
      select 1
      from public.bus_routes br
      where br.id = bus_stops.route_id
    )
  );

drop policy if exists bus_stops_platform_admin_update on public.bus_stops;
create policy bus_stops_platform_admin_update
  on public.bus_stops
  for update
  to authenticated
  using (auth.email() = 'tobby79@naver.com')
  with check (
    auth.email() = 'tobby79@naver.com'
    and exists (
      select 1
      from public.bus_routes br
      where br.id = bus_stops.route_id
    )
  );

drop policy if exists bus_stops_platform_admin_delete on public.bus_stops;
create policy bus_stops_platform_admin_delete
  on public.bus_stops
  for delete
  to authenticated
  using (auth.email() = 'tobby79@naver.com');

commit;
