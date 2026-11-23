begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Earlier request-log evidence has a different measurement method from browser tracking.
create table if not exists stroked_analytics.historical_activity (
  source_key text primary key,
  source text not null check (source = 'supabase_event_list_logs'),
  window_start timestamptz not null,
  window_end timestamptz not null check (window_end > window_start),
  captured_at timestamptz not null default now(),
  requests bigint not null check (requests >= 0),
  browser_network_combinations bigint not null check (browser_network_combinations >= 0 and browser_network_combinations <= requests),
  method text not null
);
alter table stroked_analytics.historical_activity enable row level security;
revoke all on stroked_analytics.historical_activity from public, anon, authenticated;
grant all on stroked_analytics.historical_activity to service_role;

insert into stroked_analytics.historical_activity
  (source_key, source, window_start, window_end, requests, browser_network_combinations, method)
values ('supabase_event_list_logs_2026_11_23_morning', 'supabase_event_list_logs',
  '2026-11-23T12:00:00Z', '2026-11-23T16:46:31.428973Z', 34, 15,
  'Successful event-list requests, deduplicated by IP address and browser user agent for the connection estimate. Common bot agents and authenticated administrator requests are excluded. Refreshes, signed-out owner devices and site testing may be included. Connections may overlap with later tracked visitors.')
on conflict (source_key) do nothing;

create or replace function public.stroked_live_v55_admin_traffic_stats(p_month date default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  today date := (now() at time zone 'America/Halifax')::date;
  selected_month date := date_trunc('month', coalesce(p_month, today))::date;
  next_month date := (selected_month + interval '1 month')::date;
  began timestamptz;
  began_day date;
begin
  perform stroked_live_v55.verified_uid();
  if not stroked_live_v55.is_admin() then
    raise exception 'Administrator only' using errcode = '42501';
  end if;
  if selected_month < date '2026-11-01' or selected_month > today then
    raise exception 'Choose a recorded month' using errcode = '22023';
  end if;
  select tracking_started_at into began from stroked_analytics.settings;
  began_day := (began at time zone 'America/Halifax')::date;
  return jsonb_build_object(
    'timezone', 'America/Halifax', 'tracking_started_at', began, 'updated_at', now(),
    'month', selected_month,
    'summary', coalesce((select to_jsonb(m) - 'month' from stroked_analytics.monthly m
      where month = selected_month), '{"visitors":0,"visits":0,"page_views":0}'::jsonb),
    'days', coalesce((select jsonb_agg(jsonb_build_object('day', series.day::date,
        'visitors', coalesce(d.visitors, 0), 'visits', coalesce(d.visits, 0),
        'page_views', coalesce(d.page_views, 0)) order by series.day)
      from generate_series(greatest(selected_month, began_day), least(next_month - 1, today), interval '1 day') series(day)
      left join stroked_analytics.daily d on d.day = series.day::date
      where began is not null), '[]'::jsonb),
    'months', coalesce((select jsonb_agg(jsonb_build_object('month', series.month::date,
        'visitors', coalesce(m.visitors, 0), 'visits', coalesce(m.visits, 0),
        'page_views', coalesce(m.page_views, 0)) order by series.month desc)
      from generate_series(date_trunc('month', began_day), date_trunc('month', today), interval '1 month') series(month)
      left join stroked_analytics.monthly m on m.month = series.month::date
      where began is not null), '[]'::jsonb),
    'historical_activity', coalesce((select jsonb_agg(to_jsonb(h) - 'source_key' order by h.window_start)
      from stroked_analytics.historical_activity h
      where h.window_start < (next_month::timestamp at time zone 'America/Halifax')
        and h.window_end > (selected_month::timestamp at time zone 'America/Halifax')), '[]'::jsonb),
    'sources', coalesce((select jsonb_agg(to_jsonb(s) order by s.visits desc, s.source)
      from (select source, sum(visits) as visits from stroked_analytics.sources
        where day >= selected_month and day < next_month group by source) s), '[]'::jsonb)
  );
end $$;
revoke all on function public.stroked_live_v55_admin_traffic_stats(date) from public, anon, authenticated;
grant execute on function public.stroked_live_v55_admin_traffic_stats(date) to authenticated;

notify pgrst, 'reload schema';
commit;
