begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

alter table stroked_analytics.settings add column action_started_at timestamptz not null default now();
create table stroked_analytics.action_daily (
  day date not null,
  action text not null check (action in ('event_open','share_click','account_setup','rsvp_save')),
  target_key text not null,
  source text not null,
  campaign text not null default '',
  total bigint not null default 0 check (total>=0),
  primary key(day,action,target_key,source,campaign)
);
alter table stroked_analytics.action_daily enable row level security;
revoke all on stroked_analytics.action_daily from public,anon,authenticated;
grant all on stroked_analytics.action_daily to service_role;

-- Receipts and changing network hashes use the existing two-day cleanup.
-- No browser, account, email, raw address or full referring URL is stored here.
create function public.stroked_record_event_action(
  p_event_id uuid,p_visitor_id uuid,p_network_hash text,p_source text,
  p_action text,p_target_id uuid,p_campaign text default '',p_user_id uuid default null
) returns boolean language plpgsql security definer set search_path='' as $$
declare stamp timestamptz:=now(); today date:=(stamp at time zone 'America/Halifax')::date;
  limits stroked_analytics.rate_limits%rowtype; changed integer;
begin
  if p_event_id is null or p_visitor_id is null or p_target_id is null
    or p_network_hash is null or p_network_hash !~ '^[a-f0-9]{64}$'
    or p_action is null or p_action not in ('event_open','share_click')
    or p_source is null or p_source not in ('direct','facebook','instagram','google','bing','other','internal')
    or p_campaign is null or p_campaign not in ('','facebook-launch','ark-clubs','peisa','atvans','quad-nb','snowmobile-nb','moto-canada','cma','event-share','other') then
    raise exception 'Invalid event action' using errcode='22023';
  end if;
  if exists(select 1 from public.event_admins where user_id=p_user_id) then return false;end if;
  if not exists(select 1 from public.stroked_v5_events where id=p_target_id and status='approved') then return false;end if;
  insert into stroked_analytics.rate_limits as current_limit(network_hash,minute,minute_hits,day_hits,updated_at)
  values(p_network_hash,date_trunc('minute',stamp),1,1,stamp)
  on conflict(network_hash) do update set minute=excluded.minute,
    minute_hits=case when current_limit.minute=excluded.minute then current_limit.minute_hits+1 else 1 end,
    day_hits=current_limit.day_hits+1,updated_at=stamp returning * into limits;
  if limits.minute_hits>120 or limits.day_hits>2000 then return false;end if;
  insert into stroked_analytics.receipts(event_id) values(p_event_id) on conflict do nothing;
  get diagnostics changed=row_count;
  if changed=0 then return false;end if;
  insert into stroked_analytics.action_daily(day,action,target_key,source,campaign,total)
  values(today,p_action,p_target_id::text,p_source,p_campaign,1)
  on conflict(day,action,target_key,source,campaign) do update set total=stroked_analytics.action_daily.total+1;
  return true;
end $$;
revoke all on function public.stroked_record_event_action(uuid,uuid,text,text,text,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.stroked_record_event_action(uuid,uuid,text,text,text,uuid,text,uuid) to service_role;

-- These operational conversion counters count actual saved changes, not button presses.
create function stroked_analytics.record_conversion() returns trigger
language plpgsql security definer set search_path='' as $$
declare action_name text; target text:='site';
begin
  if exists(select 1 from public.event_admins where user_id=new.user_id) then return new;end if;
  if tg_table_schema='stroked_live_v55' and tg_table_name='accounts' then
    action_name:='account_setup';
  else
    if new.response not in ('going','interested') then return new;end if;
    if tg_op='UPDATE' and new.response is not distinct from old.response and new.guests is not distinct from old.guests then return new;end if;
    action_name:='rsvp_save';target:=new.event_id::text;
  end if;
  insert into stroked_analytics.action_daily(day,action,target_key,source,campaign,total)
  values((now() at time zone 'America/Halifax')::date,action_name,target,'account','',1)
  on conflict(day,action,target_key,source,campaign) do update set total=stroked_analytics.action_daily.total+1;
  return new;
end $$;
revoke all on function stroked_analytics.record_conversion() from public,anon,authenticated;
create trigger stroked_account_setup_count after insert on stroked_live_v55.accounts
for each row execute function stroked_analytics.record_conversion();
create trigger stroked_rsvp_save_count after insert or update of response,guests on public.stroked_v54_rsvps
for each row execute function stroked_analytics.record_conversion();

create function public.stroked_live_v55_admin_engagement_stats() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  perform stroked_live_v55.verified_uid();
  if not stroked_live_v55.is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
  return jsonb_build_object('started_at',(select action_started_at from stroked_analytics.settings),
    'days',coalesce((select jsonb_agg(jsonb_build_object('day',a.day,'action',a.action,'event_id',nullif(a.target_key,'site'),
      'event_name',case when a.target_key='site' then 'Site' else coalesce(e.payload->>'name','Event no longer published') end,
      'source',a.source,'campaign',a.campaign,'total',a.total) order by a.day desc,a.action,a.target_key)
      from stroked_analytics.action_daily a left join public.stroked_v5_events e on e.id::text=a.target_key and e.status='approved'),'[]'::jsonb));
end $$;
revoke all on function public.stroked_live_v55_admin_engagement_stats() from public,anon,authenticated;
grant execute on function public.stroked_live_v55_admin_engagement_stats() to authenticated;
notify pgrst,'reload schema';
commit;
