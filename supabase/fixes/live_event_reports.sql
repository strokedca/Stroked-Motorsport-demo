-- Reports stay private and never change an event without administrator review.
create table stroked_live_v55.event_reports (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.stroked_v5_events(id) on delete cascade,
  reported_by uuid not null references auth.users(id) on delete cascade,
  issue text not null check (length(trim(issue)) between 5 and 1000),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id)
);
alter table stroked_live_v55.event_reports enable row level security;
revoke all on stroked_live_v55.event_reports from public, anon, authenticated;
create index event_reports_reporter_time on stroked_live_v55.event_reports(reported_by,created_at);

create function stroked_live_v55.report_event(p_event_id uuid,p_issue text)
returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); v uuid;
begin
  if u is null then raise exception 'Sign in to report incorrect event information'; end if;
  if not exists(select 1 from auth.users where id=u and email_confirmed_at is not null) then raise exception 'Confirm your email before reporting'; end if;
  if p_issue is null or length(trim(p_issue)) not between 5 and 1000 then raise exception 'Describe the problem in 5 to 1000 characters'; end if;
  if not exists(select 1 from public.stroked_v5_events where id=p_event_id and status='approved') then raise exception 'This public event is no longer available'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(u::text));
  if exists(select 1 from stroked_live_v55.event_reports where reported_by=u and created_at>now()-interval '1 minute')
     or (select count(*) from stroked_live_v55.event_reports where reported_by=u and created_at>now()-interval '1 hour')>=5 then
    raise exception 'Please wait before sending another report';
  end if;
  insert into stroked_live_v55.event_reports(event_id,reported_by,issue) values(p_event_id,u,trim(p_issue)) returning id into v;
  return v;
end $$;

create function stroked_live_v55.admin_reports()
returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not stroked_live_v55.is_admin() then raise exception 'Administrator access required'; end if;
  return query select jsonb_build_object('id',r.id,'event_id',r.event_id,'event_name',e.payload->>'name','issue',r.issue,'created_at',r.created_at)
  from stroked_live_v55.event_reports r join public.stroked_v5_events e on e.id=r.event_id
  where r.resolved_at is null order by r.created_at limit 200;
end $$;

create function stroked_live_v55.resolve_report(p_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if not stroked_live_v55.is_admin() then raise exception 'Administrator access required'; end if;
  update stroked_live_v55.event_reports set resolved_at=now(),resolved_by=auth.uid() where id=p_id and resolved_at is null;
  return found;
end $$;

create function public.stroked_live_v55_report_event(p_event_id uuid,p_issue text)
returns uuid language sql set search_path='' as $$ select stroked_live_v55.report_event(p_event_id,p_issue); $$;
create function public.stroked_live_v55_admin_reports()
returns setof jsonb language sql stable set search_path='' as $$ select * from stroked_live_v55.admin_reports(); $$;
create function public.stroked_live_v55_resolve_report(p_id uuid)
returns boolean language sql set search_path='' as $$ select stroked_live_v55.resolve_report(p_id); $$;

revoke all on function stroked_live_v55.report_event(uuid,text),stroked_live_v55.admin_reports(),stroked_live_v55.resolve_report(uuid),public.stroked_live_v55_report_event(uuid,text),public.stroked_live_v55_admin_reports(),public.stroked_live_v55_resolve_report(uuid) from public,anon;
grant execute on function stroked_live_v55.report_event(uuid,text),stroked_live_v55.admin_reports(),stroked_live_v55.resolve_report(uuid),public.stroked_live_v55_report_event(uuid,text),public.stroked_live_v55_admin_reports(),public.stroked_live_v55_resolve_report(uuid) to authenticated;
