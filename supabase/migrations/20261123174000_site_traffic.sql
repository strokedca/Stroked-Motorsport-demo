begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

create schema if not exists stroked_analytics;
revoke all on schema stroked_analytics from public, anon, authenticated;
grant usage on schema stroked_analytics to service_role;

create table stroked_analytics.settings (
  id boolean primary key default true check (id),
  tracking_started_at timestamptz,
  cleaned_on date
);
insert into stroked_analytics.settings(id) values (true);

-- Aggregate history survives removal of the short-lived deduplication keys.
create table stroked_analytics.daily (
  day date primary key,
  visitors bigint not null default 0,
  visits bigint not null default 0,
  page_views bigint not null default 0
);
create table stroked_analytics.monthly (
  month date primary key,
  visitors bigint not null default 0,
  visits bigint not null default 0,
  page_views bigint not null default 0
);
create table stroked_analytics.sources (
  day date not null,
  source text not null,
  visits bigint not null default 0,
  primary key (day, source)
);
create table stroked_analytics.daily_visitors (
  day date not null,
  visitor_id uuid not null,
  primary key (day, visitor_id)
);
create table stroked_analytics.monthly_visitors (
  month date not null,
  visitor_id uuid not null,
  primary key (month, visitor_id)
);
create table stroked_analytics.sessions (
  visitor_id uuid primary key,
  last_seen timestamptz not null
);
create table stroked_analytics.receipts (
  event_id uuid primary key,
  received_at timestamptz not null default now()
);
create index on stroked_analytics.receipts(received_at);
create table stroked_analytics.rate_limits (
  network_hash text primary key,
  minute timestamptz not null,
  minute_hits integer not null,
  day_hits integer not null,
  updated_at timestamptz not null
);

do $tables$
declare name text;
begin
  foreach name in array array['settings','daily','monthly','sources','daily_visitors',
    'monthly_visitors','sessions','receipts','rate_limits'] loop
    execute format('alter table stroked_analytics.%I enable row level security', name);
    execute format('revoke all on stroked_analytics.%I from public, anon, authenticated', name);
    execute format('grant all on stroked_analytics.%I to service_role', name);
  end loop;
end $tables$;

create function stroked_analytics.prune() returns void
language plpgsql security definer set search_path = '' as $$
declare today date := (now() at time zone 'America/Halifax')::date;
begin
  delete from stroked_analytics.daily_visitors where day < today - 1;
  delete from stroked_analytics.monthly_visitors
    where month < (date_trunc('month', today) - interval '1 month')::date;
  delete from stroked_analytics.sessions where last_seen < now() - interval '2 days';
  delete from stroked_analytics.receipts where received_at < now() - interval '2 days';
  delete from stroked_analytics.rate_limits where updated_at < now() - interval '2 days';
end $$;
revoke all on function stroked_analytics.prune() from public, anon, authenticated;
grant execute on function stroked_analytics.prune() to service_role;

-- Only the collector can supply a verified account ID and a network HMAC.
-- The collector checks the live origin, public API key and common bot agents.
create function public.stroked_record_site_visit(
  p_event_id uuid, p_visitor_id uuid, p_network_hash text,
  p_source text, p_user_id uuid default null
) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  stamp timestamptz := now();
  today date := (stamp at time zone 'America/Halifax')::date;
  this_month date := date_trunc('month', today)::date;
  this_minute timestamptz := date_trunc('minute', stamp);
  limits stroked_analytics.rate_limits%rowtype;
  previous_seen timestamptz;
  new_visit integer;
  daily_new integer;
  monthly_new integer;
  changed integer;
begin
  if p_event_id is null or p_visitor_id is null or p_network_hash is null
    or p_network_hash !~ '^[a-f0-9]{64}$' or p_source is null
    or p_source not in ('direct','facebook','instagram','google','bing','other','internal') then
    raise exception 'Invalid traffic record' using errcode = '22023';
  end if;
  if exists (select 1 from public.event_admins where user_id = p_user_id) then
    return false;
  end if;

  insert into stroked_analytics.rate_limits as current_limit
    (network_hash, minute, minute_hits, day_hits, updated_at)
  values (p_network_hash, this_minute, 1, 1, stamp)
  on conflict (network_hash) do update set
    minute = excluded.minute,
    minute_hits = case when current_limit.minute = excluded.minute
      then current_limit.minute_hits + 1 else 1 end,
    day_hits = current_limit.day_hits + 1,
    updated_at = stamp
  returning * into limits;
  if limits.minute_hits > 120 or limits.day_hits > 2000 then return false; end if;

  insert into stroked_analytics.receipts(event_id) values (p_event_id)
    on conflict do nothing;
  get diagnostics changed = row_count;
  if changed = 0 then return false; end if;

  -- Serializing a browser's requests prevents parallel tabs creating two visits.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_visitor_id::text, 0));
  select last_seen into previous_seen from stroked_analytics.sessions where visitor_id = p_visitor_id;
  new_visit := case when previous_seen is null or previous_seen <= stamp - interval '30 minutes' then 1 else 0 end;
  insert into stroked_analytics.sessions(visitor_id, last_seen) values (p_visitor_id, stamp)
    on conflict (visitor_id) do update set last_seen = greatest(stroked_analytics.sessions.last_seen, excluded.last_seen);

  insert into stroked_analytics.daily_visitors values (today, p_visitor_id) on conflict do nothing;
  get diagnostics daily_new = row_count;
  insert into stroked_analytics.monthly_visitors values (this_month, p_visitor_id) on conflict do nothing;
  get diagnostics monthly_new = row_count;

  insert into stroked_analytics.daily values (today, daily_new, new_visit, 1)
    on conflict (day) do update set
      visitors = stroked_analytics.daily.visitors + excluded.visitors,
      visits = stroked_analytics.daily.visits + excluded.visits,
      page_views = stroked_analytics.daily.page_views + 1;
  insert into stroked_analytics.monthly values (this_month, monthly_new, new_visit, 1)
    on conflict (month) do update set
      visitors = stroked_analytics.monthly.visitors + excluded.visitors,
      visits = stroked_analytics.monthly.visits + excluded.visits,
      page_views = stroked_analytics.monthly.page_views + 1;
  if new_visit = 1 then
    insert into stroked_analytics.sources values (today, p_source, 1)
      on conflict (day, source) do update set visits = stroked_analytics.sources.visits + 1;
  end if;
  update stroked_analytics.settings set tracking_started_at = stamp where tracking_started_at is null;
  -- Also clean up on the first visit of a new local day if cron is unavailable.
  update stroked_analytics.settings set cleaned_on = today where cleaned_on is distinct from today;
  get diagnostics changed = row_count;
  if changed = 1 then perform stroked_analytics.prune(); end if;
  return true;
end $$;
revoke all on function public.stroked_record_site_visit(uuid, uuid, text, text, uuid) from public, anon, authenticated;
grant execute on function public.stroked_record_site_visit(uuid, uuid, text, text, uuid) to service_role;

create function public.stroked_live_v55_admin_traffic_stats(p_month date default null) returns jsonb
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
    'sources', coalesce((select jsonb_agg(to_jsonb(s) order by s.visits desc, s.source)
      from (select source, sum(visits) as visits from stroked_analytics.sources
        where day >= selected_month and day < next_month group by source) s), '[]'::jsonb)
  );
end $$;
revoke all on function public.stroked_live_v55_admin_traffic_stats(date) from public, anon, authenticated;
grant execute on function public.stroked_live_v55_admin_traffic_stats(date) to authenticated;

do $cleanup$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('stroked-site-traffic-cleanup', '17 5 * * *', 'select stroked_analytics.prune()');
  end if;
end $cleanup$;
notify pgrst, 'reload schema';
commit;
