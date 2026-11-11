-- V5.5 PRODUCTION. Prepared for review; apply only after explicit production approval.
-- Uses authoritative live tables directly. No testing events, profiles, RSVPs or admins are copied.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
set local search_path='';
lock table public.event_admins,public.stroked_v5_events,public.stroked_v53_profiles,
 public.stroked_v53_requests,public.stroked_v54_rsvps in share row exclusive mode;
create schema if not exists stroked_live_v55;
revoke all on schema stroked_live_v55 from public,anon,authenticated;
create table if not exists stroked_live_v55.accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 account_type text not null check(account_type in ('rider','organizer')),
 first_name text not null default '',last_name text not null default '',
 created_at timestamptz not null default now()
);
alter table stroked_live_v55.accounts enable row level security;
revoke all on all tables in schema stroked_live_v55 from public,anon,authenticated;
grant all on stroked_live_v55.accounts to service_role;
alter table public.event_admins enable row level security;
alter table public.stroked_v5_events enable row level security;
alter table public.stroked_v53_profiles enable row level security;
alter table public.stroked_v53_requests enable row level security;
alter table public.stroked_v54_rsvps enable row level security;
revoke all on public.event_admins,public.stroked_v5_events,public.stroked_v53_profiles,
 public.stroked_v53_requests,public.stroked_v54_rsvps from public,anon,authenticated;

-- Preserve existing requests and give their next review a current live-event baseline.
-- Reapplication never replaces an existing baseline or changes an approval decision.
alter table public.stroked_v53_requests add column if not exists base_payload jsonb;
update public.stroked_v53_requests r set base_payload=e.payload
 from public.stroked_v5_events e where e.id=r.event_id and r.base_payload is null;
alter table public.stroked_v53_requests alter column base_payload set not null;
create index if not exists v55_live_events_reviewer on public.stroked_v5_events(reviewed_by);
create index if not exists v55_live_requests_event on public.stroked_v53_requests(event_id,status);
create index if not exists v55_live_requests_creator on public.stroked_v53_requests(created_by);
create index if not exists v55_live_requests_reviewer on public.stroked_v53_requests(reviewed_by);

-- Privileged implementations stay outside the exposed public schema.
-- Organizer is a free, self-service preference. It never grants administration or bypasses approval.
create or replace function stroked_live_v55.verified_uid() returns uuid
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid();
begin
  if u is null or not exists(select 1 from auth.users where id=u and email_confirmed_at is not null) then
    raise exception 'Sign in with a verified email address' using errcode='42501';
  end if;
  return u;
end $$;
create or replace function stroked_live_v55.is_admin() returns boolean
language sql stable security definer set search_path='' as $$
select exists(select 1 from public.event_admins where user_id=auth.uid());
$$;

create or replace function stroked_live_v55.my_account() returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_live_v55.verified_uid();m jsonb;
begin
  select raw_user_meta_data into m from auth.users where id=u;
  insert into stroked_live_v55.accounts(user_id,account_type,first_name,last_name)
  values(u,case when m->>'account_type'='organizer'
    or exists(select 1 from public.stroked_v5_events where created_by=u)
    or exists(select 1 from public.stroked_v53_profiles where user_id=u)
    then 'organizer' else 'rider' end,left(trim(coalesce(m->>'first_name','')),80),left(trim(coalesce(m->>'last_name','')),80))
  on conflict do nothing;
  return (select jsonb_build_object('account_type',a.account_type,'first_name',a.first_name,'last_name',a.last_name,
    'is_admin',stroked_live_v55.is_admin(),'profile',coalesce((select to_jsonb(p)-'user_id'-'updated_at' from public.stroked_v53_profiles p where p.user_id=u),'{}'::jsonb))
    from stroked_live_v55.accounts a where a.user_id=u);
end $$;
create or replace function stroked_live_v55.require_organizer() returns uuid
language plpgsql security definer set search_path='' as $$
declare a jsonb:=stroked_live_v55.my_account();
begin
  if a->>'account_type'<>'organizer' and not (a->>'is_admin')::boolean then
    raise exception 'An organizer account is required' using errcode='42501';
  end if;
  return auth.uid();
end $$;
create or replace function stroked_live_v55.become_organizer() returns boolean
language plpgsql security definer set search_path='' as $$
begin
  perform stroked_live_v55.my_account();
  update stroked_live_v55.accounts set account_type='organizer' where user_id=auth.uid();
  return true;
end $$;

create or replace function stroked_live_v55.save_profile(p_profile jsonb) returns boolean
language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_live_v55.require_organizer();
begin
  if p_profile is null or jsonb_typeof(p_profile) is distinct from 'object' or length(p_profile::text)>2500 then raise exception 'Invalid profile';end if;
  if length(trim(coalesce(p_profile->>'organization',''))) not between 2 and 100 then raise exception 'Enter your organization name (2–100 characters)';end if;
  if coalesce(p_profile->>'public_email','')<>'' and p_profile->>'public_email' !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then raise exception 'Invalid public email';end if;
  if coalesce(p_profile->>'website','')<>'' and p_profile->>'website' !~ '^https?://[^[:space:]]+$' then raise exception 'Use an http or https website';end if;
  insert into public.stroked_v53_profiles(user_id,organization,city,region,public_email,website)
  values(u,trim(p_profile->>'organization'),left(trim(coalesce(p_profile->>'city','')),80),left(trim(coalesce(p_profile->>'region','')),80),left(trim(coalesce(p_profile->>'public_email','')),160),left(trim(coalesce(p_profile->>'website','')),300))
  on conflict(user_id) do update set organization=excluded.organization,city=excluded.city,region=excluded.region,public_email=excluded.public_email,website=excluded.website,updated_at=now();
  return true;
end $$;

-- Explicit [0-9] avoids the double-escaped date expressions in the installed legacy SQL.
create or replace function stroked_live_v55.valid_payload(p jsonb) returns jsonb
language plpgsql set search_path='' as $$
declare result jsonb;cats jsonb;sponsors jsonb:='[]';s jsonb;d date;
begin
  if p is null or jsonb_typeof(p) is distinct from 'object' or length(p::text)>12000 then raise exception 'Invalid event details';end if;
  if length(trim(coalesce(p->>'name',''))) not between 3 and 90
     or length(trim(coalesce(p->>'club',''))) not between 2 and 80
     or length(trim(coalesce(p->>'province',''))) not between 2 and 50
     or length(trim(coalesce(p->>'city',''))) not between 2 and 70
     or coalesce(p->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Complete the required event fields';end if;
  d:=(p->>'date')::date;
  if d<(now() at time zone 'America/Halifax')::date-1 or d>(now() at time zone 'America/Halifax')::date+1095 then raise exception 'Event date must be between yesterday and three years ahead';end if;
  cats:=p->'categories';
  if jsonb_typeof(cats) is distinct from 'array' then raise exception 'Choose at least one category';end if;
  if jsonb_array_length(cats) not between 1 and 8 or exists(select 1 from jsonb_array_elements_text(cats) c where c is null or c not in ('Motorcycles','Cars & trucks','Classic cars','ATVs / Off-road','Snowmobiles','Motocross / Dirt track')) then raise exception 'Choose valid event categories';end if;
  if coalesce(p->>'status','Scheduled') not in ('Scheduled','Postponed','Rescheduled','Cancelled') then raise exception 'Invalid event status';end if;
  if coalesce(p->>'province','')='United States' and length(trim(coalesce(p->>'state','')))=0 then raise exception 'Choose a U.S. state';end if;
  if p ? 'sponsors' and jsonb_typeof(p->'sponsors') is distinct from 'array' then raise exception 'Invalid sponsors';end if;
  if jsonb_array_length(coalesce(p->'sponsors','[]'))>10 then raise exception 'Use at most 10 sponsors';end if;
  for s in select value from jsonb_array_elements(coalesce(p->'sponsors','[]')) loop
    if jsonb_typeof(s) is distinct from 'object' or length(trim(coalesce(s->>'name',''))) not between 1 and 120 then raise exception 'Invalid sponsor name';end if;
    if coalesce(s->>'link','')<>'' and s->>'link' !~ '^https?://[^[:space:]]+$' then raise exception 'Invalid sponsor link';end if;
    sponsors:=sponsors||jsonb_build_array(jsonb_build_object('name',s->>'name','contribution',left(coalesce(s->>'contribution',''),220),'link',left(coalesce(s->>'link',''),300)));
  end loop;
  result:=jsonb_build_object('name',trim(p->>'name'),'club',trim(p->>'club'),'date',p->>'date','categories',cats,'province',trim(p->>'province'),'city',trim(p->>'city'),'sponsors',sponsors,'status',coalesce(p->>'status','Scheduled'));
  select result||jsonb_object_agg(k,left(trim(coalesce(p->>k,'')),n)) into result from (values('state',50),('time',5),('rain',10),('startLocation',180),('endLocation',180),('registration',5),('ksu',5),('organizerContact',220),('stops',700),('food',400),('details',600)) f(k,n);
  return result;
end $$;
create or replace function stroked_live_v55.counts(p_event_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
select jsonb_build_object('going',count(*) filter(where response='going'),'interested',count(*) filter(where response='interested'),'guests',coalesce(sum(guests) filter(where response='going'),0))
from public.stroked_v54_rsvps where event_id=p_event_id;
$$;
create or replace function stroked_live_v55.public_events() returns setof jsonb
language sql stable security definer set search_path='' as $$
select jsonb_build_object('id',e.id,'payload',e.payload,'created_at',e.created_at,'counts',stroked_live_v55.counts(e.id),'organizer',jsonb_build_object('organization',p.organization,'city',p.city,'region',p.region,'public_email',p.public_email,'website',p.website))
from public.stroked_v5_events e left join public.stroked_v53_profiles p on p.user_id=e.created_by where e.status='approved' order by e.created_at desc limit 2000;
$$;
create or replace function stroked_live_v55.submit(p_payload jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_live_v55.require_organizer();v uuid;p jsonb:=stroked_live_v55.valid_payload(p_payload);
begin
  insert into public.stroked_v5_events(created_by,payload) values(u,p) returning id into v;
  return v;
end $$;
create or replace function stroked_live_v55.my_events() returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=stroked_live_v55.verified_uid();
begin
  return query select jsonb_build_object('id',e.id,'payload',e.payload,'created_at',e.created_at,'status',e.status,'review_note',e.review_note,'counts',stroked_live_v55.counts(e.id)) from public.stroked_v5_events e where created_by=u order by created_at desc limit 250;
end $$;
create or replace function stroked_live_v55.admin_events() returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  perform stroked_live_v55.verified_uid();if not stroked_live_v55.is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
  return query select jsonb_build_object('id',e.id,'payload',e.payload,'created_at',e.created_at,'status',e.status,'review_note',e.review_note) from public.stroked_v5_events e order by case when status='pending' then 0 else 1 end,created_at desc limit 500;
end $$;
create or replace function stroked_live_v55.review(p_id uuid,p_decision text,p_note text default '') returns boolean
language plpgsql security definer set search_path='' as $$
begin
  perform stroked_live_v55.verified_uid();if not stroked_live_v55.is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
  if p_decision is null or p_decision not in ('approved','rejected') then raise exception 'Invalid review decision';end if;
  update public.stroked_v5_events set status=p_decision,reviewed_at=now(),reviewed_by=auth.uid(),review_note=left(coalesce(p_note,''),500) where id=p_id and status='pending';
  return found;
end $$;
create or replace function stroked_live_v55.request_change(p_event_id uuid,p_payload jsonb,p_action text) returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_live_v55.require_organizer();e public.stroked_v5_events%rowtype;p jsonb;v uuid;
begin
  if p_action is null or p_action not in ('edit','cancel') then raise exception 'Invalid request type';end if;
  select * into e from public.stroked_v5_events where id=p_event_id and created_by=u for update;
  if not found then raise exception 'Event not found or not yours' using errcode='42501';end if;
  p:=case when p_action='edit' then stroked_live_v55.valid_payload(p_payload) else e.payload end;
  if exists(select 1 from public.stroked_v53_requests where event_id=e.id and status='pending') then raise exception 'This event already has a pending request';end if;
  insert into public.stroked_v53_requests(event_id,created_by,payload,base_payload,action) values(e.id,u,p,e.payload,p_action) returning id into v;
  return v;
end $$;
create or replace function stroked_live_v55.admin_requests() returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  perform stroked_live_v55.verified_uid();if not stroked_live_v55.is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
  return query select jsonb_build_object('id',r.id,'event_id',r.event_id,'payload',r.payload,'action',r.action,'status',r.status,'created_at',r.created_at,'organizer',coalesce((select organization from public.stroked_v53_profiles where user_id=r.created_by),'')) from public.stroked_v53_requests r where r.status='pending' order by r.created_at limit 250;
end $$;
create or replace function stroked_live_v55.review_request(p_id uuid,p_decision text,p_note text default '') returns boolean
language plpgsql security definer set search_path='' as $$
declare r public.stroked_v53_requests%rowtype;e public.stroked_v5_events%rowtype;
begin
  perform stroked_live_v55.verified_uid();if not stroked_live_v55.is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
  if p_decision is null or p_decision not in ('approved','rejected') then raise exception 'Invalid review decision';end if;
  select * into r from public.stroked_v53_requests where id=p_id and status='pending' for update;
  if not found then return false;end if;
  select * into e from public.stroked_v5_events where id=r.event_id for update;
  if p_decision='approved' then
    if r.base_payload<>e.payload then raise exception 'The event changed after this request. Reject it and ask the organizer to resubmit.';end if;
    update public.stroked_v5_events set payload=case when r.action='cancel' then jsonb_set(e.payload,'{status}','"Cancelled"') else stroked_live_v55.valid_payload(r.payload) end,
      status=case when r.action='cancel' and e.status<>'approved' then 'rejected' else 'approved' end,
      reviewed_at=now(),reviewed_by=auth.uid(),review_note=left(coalesce(p_note,''),500) where id=r.event_id;
  end if;
  update public.stroked_v53_requests set status=p_decision,reviewed_at=now(),reviewed_by=auth.uid(),review_note=left(coalesce(p_note,''),500) where id=p_id;
  return true;
end $$;
create or replace function stroked_live_v55.my_rsvp(p_event_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=stroked_live_v55.verified_uid();
begin
  return (select jsonb_build_object('response',r.response,'guests',r.guests) from public.stroked_v54_rsvps r where r.event_id=p_event_id and r.user_id=u);
end $$;
create or replace function stroked_live_v55.save_rsvp(p_event_id uuid,p_response text,p_guests integer default 0) returns boolean
language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_live_v55.verified_uid();e public.stroked_v5_events%rowtype;
begin
  if p_response is null or p_response not in ('going','interested','not_going') then raise exception 'Invalid RSVP';end if;
  if p_guests is null or p_guests not between 0 and 10 then raise exception 'Guests must be between 0 and 10';end if;
  -- A person may remove their own RSVP even after cancellation or the event date.
  if p_response='not_going' then delete from public.stroked_v54_rsvps where event_id=p_event_id and user_id=u;return true;end if;
  select * into e from public.stroked_v5_events where id=p_event_id for share;
  if not found or e.status<>'approved' or coalesce(e.payload->>'status','Scheduled')='Cancelled'
    or coalesce(e.payload->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or (e.payload->>'date')::date<(now() at time zone 'America/Halifax')::date then raise exception 'This event is not available for RSVP';end if;
  insert into public.stroked_v54_rsvps(event_id,user_id,response,guests) values(p_event_id,u,p_response,case when p_response='going' then p_guests else 0 end)
  on conflict(event_id,user_id) do update set response=excluded.response,guests=excluded.guests,updated_at=now();return true;
end $$;


create or replace function stroked_live_v55.legacy_is_admin() returns boolean
language plpgsql stable security definer set search_path='' as $$
begin perform stroked_live_v55.verified_uid();return stroked_live_v55.is_admin();end $$;
create or replace function stroked_live_v55.legacy_my_profile() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=stroked_live_v55.verified_uid();
begin return (select to_jsonb(p)-'user_id'-'updated_at' from public.stroked_v53_profiles p where p.user_id=u);end $$;
create or replace function stroked_live_v55.legacy_public_organizer(p_event_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
select r->'organizer' from stroked_live_v55.public_events() r where (r->>'id')::uuid=p_event_id and r->'organizer'->>'organization' is not null;
$$;
create or replace function stroked_live_v55.legacy_public_rsvp_counts() returns setof jsonb
language sql stable security definer set search_path='' as $$
select jsonb_build_object('event_id',r->'id','going',r->'counts'->'going','interested',r->'counts'->'interested',
 'guests',r->'counts'->'guests','attendees',(r->'counts'->>'going')::bigint+(r->'counts'->>'guests')::bigint)
from stroked_live_v55.public_events() r;
$$;

-- Public endpoints and cached V5.4 clients share the same checked implementations.
create or replace function public.stroked_live_v55_my_account() returns jsonb
language sql security invoker set search_path='' as $$
select stroked_live_v55.my_account();
$$;
create or replace function public.stroked_live_v55_become_organizer() returns boolean
language sql security invoker set search_path='' as $$
select stroked_live_v55.become_organizer();
$$;
create or replace function public.stroked_live_v55_save_profile(p_profile jsonb) returns boolean
language sql security invoker set search_path='' as $$
select stroked_live_v55.save_profile(p_profile);
$$;
create or replace function public.stroked_live_v55_public_events() returns setof jsonb
language sql stable security invoker set search_path='' as $$
select * from stroked_live_v55.public_events();
$$;
create or replace function public.stroked_live_v55_submit(p_payload jsonb) returns uuid
language sql security invoker set search_path='' as $$
select stroked_live_v55.submit(p_payload);
$$;
create or replace function public.stroked_live_v55_my_events() returns setof jsonb
language sql stable security invoker set search_path='' as $$
select * from stroked_live_v55.my_events();
$$;
create or replace function public.stroked_live_v55_admin_events() returns setof jsonb
language sql stable security invoker set search_path='' as $$
select * from stroked_live_v55.admin_events();
$$;
create or replace function public.stroked_live_v55_review(p_id uuid,p_decision text,p_note text default '') returns boolean
language sql security invoker set search_path='' as $$
select stroked_live_v55.review(p_id,p_decision,p_note);
$$;
create or replace function public.stroked_live_v55_request_change(p_event_id uuid,p_payload jsonb,p_action text) returns uuid
language sql security invoker set search_path='' as $$
select stroked_live_v55.request_change(p_event_id,p_payload,p_action);
$$;
create or replace function public.stroked_live_v55_admin_requests() returns setof jsonb
language sql stable security invoker set search_path='' as $$
select * from stroked_live_v55.admin_requests();
$$;
create or replace function public.stroked_live_v55_review_request(p_id uuid,p_decision text,p_note text default '') returns boolean
language sql security invoker set search_path='' as $$
select stroked_live_v55.review_request(p_id,p_decision,p_note);
$$;
create or replace function public.stroked_live_v55_my_rsvp(p_event_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
select stroked_live_v55.my_rsvp(p_event_id);
$$;
create or replace function public.stroked_live_v55_save_rsvp(p_event_id uuid,p_response text,p_guests integer default 0) returns boolean
language sql security invoker set search_path='' as $$
select stroked_live_v55.save_rsvp(p_event_id,p_response,p_guests);
$$;
create or replace function public.stroked_v5_is_admin() returns boolean
language sql stable security invoker set search_path='' as $$
select stroked_live_v55.legacy_is_admin();
$$;
create or replace function public.stroked_v5_public_events() returns setof jsonb
language sql stable security invoker set search_path='' as $$
select * from stroked_live_v55.public_events();
$$;
create or replace function public.stroked_v5_my_events() returns setof jsonb
language sql stable security invoker set search_path='' as $$
select * from stroked_live_v55.my_events();
$$;
create or replace function public.stroked_v5_admin_events() returns setof jsonb
language sql stable security invoker set search_path='' as $$
select * from stroked_live_v55.admin_events();
$$;
create or replace function public.stroked_v5_submit(p_payload jsonb) returns uuid
language sql security invoker set search_path='' as $$
select stroked_live_v55.submit(p_payload);
$$;
create or replace function public.stroked_v5_review(p_id uuid,p_decision text,p_note text default '') returns boolean
language sql security invoker set search_path='' as $$
select stroked_live_v55.review(p_id,p_decision,p_note);
$$;
create or replace function public.stroked_v53_my_profile() returns jsonb
language sql stable security invoker set search_path='' as $$
select stroked_live_v55.legacy_my_profile();
$$;
create or replace function public.stroked_v53_save_profile(p_profile jsonb) returns boolean
language sql security invoker set search_path='' as $$
select stroked_live_v55.save_profile(p_profile);
$$;
create or replace function public.stroked_v53_request_change(p_event_id uuid,p_payload jsonb,p_action text) returns uuid
language sql security invoker set search_path='' as $$
select stroked_live_v55.request_change(p_event_id,p_payload,p_action);
$$;
create or replace function public.stroked_v53_admin_requests() returns setof jsonb
language sql stable security invoker set search_path='' as $$
select * from stroked_live_v55.admin_requests();
$$;
create or replace function public.stroked_v53_review_request(p_id uuid,p_decision text,p_note text default '') returns boolean
language sql security invoker set search_path='' as $$
select stroked_live_v55.review_request(p_id,p_decision,p_note);
$$;
create or replace function public.stroked_v54_my_rsvp(p_event_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
select stroked_live_v55.my_rsvp(p_event_id);
$$;
create or replace function public.stroked_v54_save_rsvp(p_event_id uuid,p_response text,p_guests integer default 0) returns boolean
language sql security invoker set search_path='' as $$
select stroked_live_v55.save_rsvp(p_event_id,p_response,p_guests);
$$;
create or replace function public.stroked_v54_public_organizer(p_event_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
select stroked_live_v55.legacy_public_organizer(p_event_id);
$$;
create or replace function public.stroked_v54_public_rsvp_counts() returns setof jsonb
language sql stable security invoker set search_path='' as $$
select * from stroked_live_v55.legacy_public_rsvp_counts();
$$;

-- Callers can use only the checked endpoints; tables and internal helpers stay inaccessible.
revoke all on all functions in schema stroked_live_v55 from public,anon,authenticated;
grant usage on schema stroked_live_v55 to anon,authenticated,service_role;
grant execute on function stroked_live_v55.my_account() to authenticated;
grant execute on function stroked_live_v55.become_organizer() to authenticated;
grant execute on function stroked_live_v55.save_profile(jsonb) to authenticated;
grant execute on function stroked_live_v55.public_events() to authenticated;
grant execute on function stroked_live_v55.submit(jsonb) to authenticated;
grant execute on function stroked_live_v55.my_events() to authenticated;
grant execute on function stroked_live_v55.admin_events() to authenticated;
grant execute on function stroked_live_v55.review(uuid,text,text) to authenticated;
grant execute on function stroked_live_v55.request_change(uuid,jsonb,text) to authenticated;
grant execute on function stroked_live_v55.admin_requests() to authenticated;
grant execute on function stroked_live_v55.review_request(uuid,text,text) to authenticated;
grant execute on function stroked_live_v55.my_rsvp(uuid) to authenticated;
grant execute on function stroked_live_v55.save_rsvp(uuid,text,integer) to authenticated;
grant execute on function stroked_live_v55.legacy_is_admin() to authenticated;
grant execute on function stroked_live_v55.legacy_my_profile() to authenticated;
grant execute on function stroked_live_v55.legacy_public_organizer(uuid) to authenticated;
grant execute on function stroked_live_v55.legacy_public_rsvp_counts() to authenticated;
grant execute on function stroked_live_v55.public_events() to anon;
grant execute on function stroked_live_v55.legacy_public_organizer(uuid) to anon;
grant execute on function stroked_live_v55.legacy_public_rsvp_counts() to anon;
do $$declare f record;begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname in ('stroked_live_v55_my_account','stroked_live_v55_become_organizer','stroked_live_v55_save_profile','stroked_live_v55_public_events','stroked_live_v55_submit','stroked_live_v55_my_events','stroked_live_v55_admin_events','stroked_live_v55_review','stroked_live_v55_request_change','stroked_live_v55_admin_requests','stroked_live_v55_review_request','stroked_live_v55_my_rsvp','stroked_live_v55_save_rsvp','stroked_v5_is_admin','stroked_v5_public_events','stroked_v5_my_events','stroked_v5_admin_events','stroked_v5_submit','stroked_v5_review','stroked_v53_my_profile','stroked_v53_save_profile','stroked_v53_request_change','stroked_v53_admin_requests','stroked_v53_review_request','stroked_v54_my_rsvp','stroked_v54_save_rsvp','stroked_v54_public_organizer','stroked_v54_public_rsvp_counts') loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
 -- Retire the unused pre-V5 write APIs without deleting their data.
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname in ('submit_event','review_event') loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 end loop;
end $$;
grant execute on function public.stroked_live_v55_public_events(),public.stroked_v5_public_events(),
 public.stroked_v54_public_organizer(uuid),public.stroked_v54_public_rsvp_counts() to anon;
notify pgrst,'reload schema';
commit;
