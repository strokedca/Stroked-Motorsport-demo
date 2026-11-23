begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Reuse the monthly report and signup rules. Visits and page views are additive.
-- Distinct monthly browser counts cannot be added to produce annual audiences.
create or replace function public.stroked_live_v55_admin_audience_stats(p_month date default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  traffic jsonb;
  members jsonb;
begin
  perform stroked_live_v55.verified_uid();
  if not stroked_live_v55.is_admin() then
    raise exception 'Administrator only' using errcode = '42501';
  end if;
  traffic := public.stroked_live_v55_admin_traffic_stats(p_month);
  members := public.stroked_live_v55_admin_signup_stats();
  return traffic || jsonb_build_object(
    'all_time', (select jsonb_build_object('visits',coalesce(sum(visits),0),
      'page_views',coalesce(sum(page_views),0)) from stroked_analytics.monthly),
    'years', coalesce((select jsonb_agg(to_jsonb(annual) order by annual.year desc)
      from (select extract(year from month)::integer as year,
        sum(visits) as visits, sum(page_views) as page_views
        from stroked_analytics.monthly group by extract(year from month)) annual), '[]'::jsonb),
    'members', jsonb_build_object('email_confirmed', members->'email_confirmed',
      'registered', members->'total'),
    'historical_activity', coalesce((select jsonb_agg(to_jsonb(h) - 'source_key' order by h.window_start)
      from stroked_analytics.historical_activity h), '[]'::jsonb)
  );
end $$;
revoke all on function public.stroked_live_v55_admin_audience_stats(date) from public, anon, authenticated;
grant execute on function public.stroked_live_v55_admin_audience_stats(date) to authenticated;
notify pgrst, 'reload schema';
commit;
