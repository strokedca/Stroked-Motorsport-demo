-- V5.5 TESTING ONLY. Additive isolation: no live tables or existing RPCs are changed.
-- The public stroked_v55_* RPCs are the only browser entry points into this schema.
begin;
create schema if not exists stroked_v55_testing;
revoke all on schema stroked_v55_testing from public, anon, authenticated;

create table if not exists stroked_v55_testing.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
create table if not exists stroked_v55_testing.accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  account_type text not null check(account_type in ('rider','organizer')),
  first_name text not null default '', last_name text not null default '',
  created_at timestamptz not null default now()
);
create table if not exists stroked_v55_testing.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  organization text not null default '',city text not null default '',region text not null default '',
  public_email text not null default '',website text not null default '',updated_at timestamptz not null default now()
);
create table if not exists stroked_v55_testing.events (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id) on delete cascade,
  payload jsonb not null,
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id),review_note text not null default ''
);
create table if not exists stroked_v55_testing.requests (
  id uuid primary key default gen_random_uuid(),event_id uuid not null references stroked_v55_testing.events(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  payload jsonb not null,base_payload jsonb not null,
  action text not null check(action in ('edit','cancel')),
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id),review_note text not null default ''
);
create table if not exists stroked_v55_testing.rsvps (
  event_id uuid not null references stroked_v55_testing.events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  response text not null check(response in ('going','interested')),
  guests integer not null default 0 check(guests between 0 and 10),
  updated_at timestamptz not null default now(),primary key(event_id,user_id)
);
create index if not exists v55_events_creator on stroked_v55_testing.events(created_by,created_at desc);
create index if not exists v55_events_status on stroked_v55_testing.events(status,created_at desc);
create index if not exists v55_events_reviewer on stroked_v55_testing.events(reviewed_by);
create index if not exists v55_requests_event on stroked_v55_testing.requests(event_id,status);
create index if not exists v55_requests_creator on stroked_v55_testing.requests(created_by);
create index if not exists v55_requests_reviewer on stroked_v55_testing.requests(reviewed_by);
create index if not exists v55_rsvps_user on stroked_v55_testing.rsvps(user_id);

-- Copy existing application data once, preserving its identity. Re-running never overwrites tests.
insert into stroked_v55_testing.admins(user_id) select user_id from public.event_admins on conflict do nothing;
insert into stroked_v55_testing.profiles select * from public.stroked_v53_profiles on conflict do nothing;
insert into stroked_v55_testing.events select * from public.stroked_v5_events on conflict do nothing;
insert into stroked_v55_testing.rsvps select * from public.stroked_v54_rsvps on conflict do nothing;
insert into stroked_v55_testing.requests(id,event_id,created_by,payload,base_payload,action,status,created_at,reviewed_at,reviewed_by,review_note)
select r.id,r.event_id,r.created_by,r.payload,e.payload,r.action,r.status,r.created_at,r.reviewed_at,r.reviewed_by,r.review_note
from public.stroked_v53_requests r join public.stroked_v5_events e on e.id=r.event_id on conflict do nothing;

alter table stroked_v55_testing.admins enable row level security;
alter table stroked_v55_testing.accounts enable row level security;
alter table stroked_v55_testing.profiles enable row level security;
alter table stroked_v55_testing.events enable row level security;
alter table stroked_v55_testing.requests enable row level security;
alter table stroked_v55_testing.rsvps enable row level security;
revoke all on all tables in schema stroked_v55_testing from public,anon,authenticated;

create or replace function stroked_v55_testing.verified_uid() returns uuid
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid();
begin
  if u is null or not exists(select 1 from auth.users where id=u and email_confirmed_at is not null) then
    raise exception 'Sign in with a verified email address' using errcode='42501';
  end if;
  return u;
end $$;
create or replace function stroked_v55_testing.is_admin() returns boolean
language sql stable security definer set search_path='' as $$
select exists(select 1 from stroked_v55_testing.admins where user_id=auth.uid());
$$;

create or replace function public.stroked_v55_my_account() returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_v55_testing.verified_uid();m jsonb;
begin
  select raw_user_meta_data into m from auth.users where id=u;
  insert into stroked_v55_testing.accounts(user_id,account_type,first_name,last_name)
  values(u,case when m->>'account_type'='organizer'
    or exists(select 1 from stroked_v55_testing.events where created_by=u)
    or exists(select 1 from stroked_v55_testing.profiles where user_id=u)
    then 'organizer' else 'rider' end,left(trim(coalesce(m->>'first_name','')),80),left(trim(coalesce(m->>'last_name','')),80))
  on conflict do nothing;
  return (select jsonb_build_object('account_type',a.account_type,'first_name',a.first_name,'last_name',a.last_name,
    'is_admin',stroked_v55_testing.is_admin(),'profile',coalesce((select to_jsonb(p)-'user_id'-'updated_at' from stroked_v55_testing.profiles p where p.user_id=u),'{}'::jsonb))
    from stroked_v55_testing.accounts a where a.user_id=u);
end $$;
create or replace function stroked_v55_testing.require_organizer() returns uuid
language plpgsql security definer set search_path='' as $$
declare a jsonb:=public.stroked_v55_my_account();
begin
  if a->>'account_type'<>'organizer' and not (a->>'is_admin')::boolean then
    raise exception 'An organizer account is required' using errcode='42501';
  end if;
  return auth.uid();
end $$;
create or replace function public.stroked_v55_become_organizer() returns boolean
language plpgsql security definer set search_path='' as $$
begin
  perform public.stroked_v55_my_account();
  update stroked_v55_testing.accounts set account_type='organizer' where user_id=auth.uid();
  return true;
end $$;

create or replace function public.stroked_v55_save_profile(p_profile jsonb) returns boolean
language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_v55_testing.require_organizer();
begin
  if p_profile is null or jsonb_typeof(p_profile) is distinct from 'object' or length(p_profile::text)>2500 then raise exception 'Invalid profile';end if;
  if length(trim(coalesce(p_profile->>'organization',''))) not between 2 and 100 then raise exception 'Enter your organization name (2–100 characters)';end if;
  if coalesce(p_profile->>'public_email','')<>'' and p_profile->>'public_email' !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then raise exception 'Invalid public email';end if;
  if coalesce(p_profile->>'website','')<>'' and p_profile->>'website' !~ '^https?://[^[:space:]]+$' then raise exception 'Use an http or https website';end if;
  insert into stroked_v55_testing.profiles(user_id,organization,city,region,public_email,website)
  values(u,trim(p_profile->>'organization'),left(trim(coalesce(p_profile->>'city','')),80),left(trim(coalesce(p_profile->>'region','')),80),left(trim(coalesce(p_profile->>'public_email','')),160),left(trim(coalesce(p_profile->>'website','')),300))
  on conflict(user_id) do update set organization=excluded.organization,city=excluded.city,region=excluded.region,public_email=excluded.public_email,website=excluded.website,updated_at=now();
  return true;
end $$;

-- Explicit [0-9] avoids the double-escaped date expressions in the installed legacy SQL.
create or replace function stroked_v55_testing.valid_payload(p jsonb) returns jsonb
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
create or replace function stroked_v55_testing.counts(p_event_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
select jsonb_build_object('going',count(*) filter(where response='going'),'interested',count(*) filter(where response='interested'),'guests',coalesce(sum(guests) filter(where response='going'),0))
from stroked_v55_testing.rsvps where event_id=p_event_id;
$$;
create or replace function public.stroked_v55_public_events() returns setof jsonb
language sql stable security definer set search_path='' as $$
select jsonb_build_object('id',e.id,'payload',e.payload,'counts',stroked_v55_testing.counts(e.id),'organizer',jsonb_build_object('organization',p.organization,'city',p.city,'region',p.region,'public_email',p.public_email,'website',p.website))
from stroked_v55_testing.events e left join stroked_v55_testing.profiles p on p.user_id=e.created_by where e.status='approved' order by e.created_at desc limit 2000;
$$;
create or replace function public.stroked_v55_submit(p_payload jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_v55_testing.require_organizer();v uuid;p jsonb:=stroked_v55_testing.valid_payload(p_payload);
begin
  insert into stroked_v55_testing.events(created_by,payload) values(u,p) returning id into v;
  return v;
end $$;
create or replace function public.stroked_v55_my_events() returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=stroked_v55_testing.verified_uid();
begin
  return query select jsonb_build_object('id',e.id,'payload',e.payload,'status',e.status,'review_note',e.review_note,'counts',stroked_v55_testing.counts(e.id)) from stroked_v55_testing.events e where created_by=u order by created_at desc limit 250;
end $$;
create or replace function public.stroked_v55_admin_events() returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  perform stroked_v55_testing.verified_uid();if not stroked_v55_testing.is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
  return query select jsonb_build_object('id',e.id,'payload',e.payload,'status',e.status,'review_note',e.review_note) from stroked_v55_testing.events e order by case when status='pending' then 0 else 1 end,created_at desc limit 500;
end $$;
create or replace function public.stroked_v55_review(p_id uuid,p_decision text,p_note text default '') returns boolean
language plpgsql security definer set search_path='' as $$
begin
  perform stroked_v55_testing.verified_uid();if not stroked_v55_testing.is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
  if p_decision is null or p_decision not in ('approved','rejected') then raise exception 'Invalid review decision';end if;
  update stroked_v55_testing.events set status=p_decision,reviewed_at=now(),reviewed_by=auth.uid(),review_note=left(coalesce(p_note,''),500) where id=p_id and status='pending';
  return found;
end $$;
create or replace function public.stroked_v55_request_change(p_event_id uuid,p_payload jsonb,p_action text) returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_v55_testing.require_organizer();e stroked_v55_testing.events%rowtype;p jsonb;v uuid;
begin
  if p_action is null or p_action not in ('edit','cancel') then raise exception 'Invalid request type';end if;
  select * into e from stroked_v55_testing.events where id=p_event_id and created_by=u for update;
  if not found then raise exception 'Event not found or not yours' using errcode='42501';end if;
  p:=case when p_action='edit' then stroked_v55_testing.valid_payload(p_payload) else e.payload end;
  if exists(select 1 from stroked_v55_testing.requests where event_id=e.id and status='pending') then raise exception 'This event already has a pending request';end if;
  insert into stroked_v55_testing.requests(event_id,created_by,payload,base_payload,action) values(e.id,u,p,e.payload,p_action) returning id into v;
  return v;
end $$;
create or replace function public.stroked_v55_admin_requests() returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  perform stroked_v55_testing.verified_uid();if not stroked_v55_testing.is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
  return query select jsonb_build_object('id',r.id,'event_id',r.event_id,'payload',r.payload,'action',r.action,'status',r.status) from stroked_v55_testing.requests r where r.status='pending' order by r.created_at limit 250;
end $$;
create or replace function public.stroked_v55_review_request(p_id uuid,p_decision text,p_note text default '') returns boolean
language plpgsql security definer set search_path='' as $$
declare r stroked_v55_testing.requests%rowtype;e stroked_v55_testing.events%rowtype;
begin
  perform stroked_v55_testing.verified_uid();if not stroked_v55_testing.is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
  if p_decision is null or p_decision not in ('approved','rejected') then raise exception 'Invalid review decision';end if;
  select * into r from stroked_v55_testing.requests where id=p_id and status='pending' for update;
  if not found then return false;end if;
  select * into e from stroked_v55_testing.events where id=r.event_id for update;
  if p_decision='approved' then
    if r.base_payload<>e.payload then raise exception 'The event changed after this request. Reject it and ask the organizer to resubmit.';end if;
    update stroked_v55_testing.events set payload=case when r.action='cancel' then jsonb_set(e.payload,'{status}','"Cancelled"') else stroked_v55_testing.valid_payload(r.payload) end,
      status=case when r.action='cancel' and e.status<>'approved' then 'rejected' else 'approved' end,
      reviewed_at=now(),reviewed_by=auth.uid(),review_note=left(coalesce(p_note,''),500) where id=r.event_id;
  end if;
  update stroked_v55_testing.requests set status=p_decision,reviewed_at=now(),reviewed_by=auth.uid(),review_note=left(coalesce(p_note,''),500) where id=p_id;
  return true;
end $$;
create or replace function public.stroked_v55_my_rsvp(p_event_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=stroked_v55_testing.verified_uid();
begin
  return (select jsonb_build_object('response',r.response,'guests',r.guests) from stroked_v55_testing.rsvps r where r.event_id=p_event_id and r.user_id=u);
end $$;
create or replace function public.stroked_v55_save_rsvp(p_event_id uuid,p_response text,p_guests integer default 0) returns boolean
language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_v55_testing.verified_uid();e stroked_v55_testing.events%rowtype;
begin
  if p_response is null or p_response not in ('going','interested','not_going') then raise exception 'Invalid RSVP';end if;
  if p_guests is null or p_guests not between 0 and 10 then raise exception 'Guests must be between 0 and 10';end if;
  -- A person may remove their own RSVP even after cancellation or the event date.
  if p_response='not_going' then delete from stroked_v55_testing.rsvps where event_id=p_event_id and user_id=u;return true;end if;
  select * into e from stroked_v55_testing.events where id=p_event_id for share;
  if not found or e.status<>'approved' or coalesce(e.payload->>'status','Scheduled')='Cancelled'
    or coalesce(e.payload->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or (e.payload->>'date')::date<(now() at time zone 'America/Halifax')::date then raise exception 'This event is not available for RSVP';end if;
  insert into stroked_v55_testing.rsvps(event_id,user_id,response,guests) values(p_event_id,u,p_response,case when p_response='going' then p_guests else 0 end)
  on conflict(event_id,user_id) do update set response=excluded.response,guests=excluded.guests,updated_at=now();return true;
end $$;

-- Revoke explicit grants as well as PUBLIC inheritance; Supabase defaults can grant both.
revoke all on all functions in schema stroked_v55_testing from public,anon,authenticated;
do $$declare f record;begin
  for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'stroked_v55_%' loop
    execute format('revoke all on function %s from public,anon,authenticated',f.signature);
    execute format('grant execute on function %s to authenticated',f.signature);
  end loop;
end $$;
grant execute on function public.stroked_v55_public_events() to anon;
notify pgrst,'reload schema';
commit;
