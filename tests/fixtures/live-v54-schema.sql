-- Schema-only fixture captured from the live V5.4 tables; no user records or credentials.
create role anon;create role authenticated;create role service_role;
create schema auth;
create table auth.users(id uuid primary key,email_confirmed_at timestamptz,raw_user_meta_data jsonb not null default '{}');
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table public.event_admins (
  user_id uuid not null,
  added_at timestamp with time zone default now() not null,
  constraint event_admins_pkey PRIMARY KEY (user_id),
  constraint event_admins_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
alter table public.event_admins enable row level security;
revoke all on public.event_admins from public,anon,authenticated;
grant all on public.event_admins to service_role;
create table public.stroked_v5_events (
  id uuid default gen_random_uuid() not null,
  created_by uuid not null,
  payload jsonb not null,
  status text default 'pending'::text not null,
  created_at timestamp with time zone default now() not null,
  reviewed_at timestamp with time zone,
  reviewed_by uuid,
  review_note text default ''::text not null,
  constraint stroked_v5_events_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint stroked_v5_events_pkey PRIMARY KEY (id),
  constraint stroked_v5_events_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id),
  constraint stroked_v5_events_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);
alter table public.stroked_v5_events enable row level security;
revoke all on public.stroked_v5_events from public,anon,authenticated;
grant all on public.stroked_v5_events to service_role;
create table public.stroked_v53_profiles (
  user_id uuid not null,
  organization text default ''::text not null,
  city text default ''::text not null,
  region text default ''::text not null,
  public_email text default ''::text not null,
  website text default ''::text not null,
  updated_at timestamp with time zone default now() not null,
  constraint stroked_v53_profiles_pkey PRIMARY KEY (user_id),
  constraint stroked_v53_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
alter table public.stroked_v53_profiles enable row level security;
revoke all on public.stroked_v53_profiles from public,anon,authenticated;
grant all on public.stroked_v53_profiles to service_role;
create table public.stroked_v53_requests (
  id uuid default gen_random_uuid() not null,
  event_id uuid not null,
  created_by uuid not null,
  payload jsonb not null,
  action text not null,
  status text default 'pending'::text not null,
  created_at timestamp with time zone default now() not null,
  reviewed_at timestamp with time zone,
  reviewed_by uuid,
  review_note text default ''::text not null,
  constraint stroked_v53_requests_action_check CHECK ((action = ANY (ARRAY['edit'::text, 'cancel'::text]))),
  constraint stroked_v53_requests_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint stroked_v53_requests_event_id_fkey FOREIGN KEY (event_id) REFERENCES stroked_v5_events(id) ON DELETE CASCADE,
  constraint stroked_v53_requests_pkey PRIMARY KEY (id),
  constraint stroked_v53_requests_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id),
  constraint stroked_v53_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);
alter table public.stroked_v53_requests enable row level security;
revoke all on public.stroked_v53_requests from public,anon,authenticated;
grant all on public.stroked_v53_requests to service_role;
create table public.stroked_v54_rsvps (
  event_id uuid not null,
  user_id uuid not null,
  response text not null,
  guests integer default 0 not null,
  updated_at timestamp with time zone default now() not null,
  constraint stroked_v54_rsvps_event_id_fkey FOREIGN KEY (event_id) REFERENCES stroked_v5_events(id) ON DELETE CASCADE,
  constraint stroked_v54_rsvps_guests_check CHECK (((guests >= 0) AND (guests <= 10))),
  constraint stroked_v54_rsvps_pkey PRIMARY KEY (event_id, user_id),
  constraint stroked_v54_rsvps_response_check CHECK ((response = ANY (ARRAY['going'::text, 'interested'::text]))),
  constraint stroked_v54_rsvps_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
alter table public.stroked_v54_rsvps enable row level security;
revoke all on public.stroked_v54_rsvps from public,anon,authenticated;
grant all on public.stroked_v54_rsvps to service_role;
CREATE OR REPLACE FUNCTION public.stroked_v53_admin_requests()
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ begin
if not public.stroked_v5_is_admin() then raise exception 'Administrator only'; end if;
return query select jsonb_build_object('id',r.id,'event_id',r.event_id,'payload',r.payload,'action',r.action,'status',r.status,'organizer',coalesce(p.organization,''),'created_at',r.created_at)
from public.stroked_v53_requests r left join public.stroked_v53_profiles p on p.user_id=r.created_by
where r.status='pending' order by r.created_at asc limit 250;
end; $function$;
revoke all on function public.stroked_v53_admin_requests() from public;
grant execute on function public.stroked_v53_admin_requests() to anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.stroked_v53_my_profile()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select jsonb_build_object('organization',organization,'city',city,'region',region,'public_email',public_email,'website',website)
from public.stroked_v53_profiles where user_id=auth.uid(); $function$;
revoke all on function public.stroked_v53_my_profile() from public;
grant execute on function public.stroked_v53_my_profile() to anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.stroked_v53_request_change(p_event_id uuid, p_payload jsonb, p_action text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v_id uuid; v_event public.stroked_v5_events%rowtype; begin
if auth.uid() is null then raise exception 'Sign in required'; end if;
select * into v_event from public.stroked_v5_events where id=p_event_id and created_by=auth.uid();
if not found then raise exception 'Event not found or not yours'; end if;
if p_action not in ('edit','cancel') then raise exception 'Invalid request type'; end if;
if p_payload is null or jsonb_typeof(p_payload)<>'object' or length(p_payload::text)>12000 then raise exception 'Invalid event details'; end if;
if p_action='edit' and (length(trim(coalesce(p_payload->>'name','')))<3 or coalesce(p_payload->>'date','') !~ '^\d{4}-\d{2}-\d{2}$') then raise exception 'Event name and date required'; end if;
if exists(select 1 from public.stroked_v53_requests where event_id=p_event_id and status='pending') then raise exception 'This event already has a pending change request'; end if;
insert into public.stroked_v53_requests(event_id,created_by,payload,action) values(p_event_id,auth.uid(),p_payload,p_action) returning id into v_id;
return v_id; end; $function$;
revoke all on function public.stroked_v53_request_change(uuid,jsonb,text) from public;
grant execute on function public.stroked_v53_request_change(uuid,jsonb,text) to anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.stroked_v53_review_request(p_id uuid, p_decision text, p_note text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare r public.stroked_v53_requests%rowtype; begin
if not public.stroked_v5_is_admin() then raise exception 'Administrator only'; end if;
if p_decision not in ('approved','rejected') then raise exception 'Invalid decision'; end if;
select * into r from public.stroked_v53_requests where id=p_id and status='pending' for update;
if not found then return false; end if;
if p_decision='approved' then
if r.action='cancel' then
update public.stroked_v5_events set status='rejected',reviewed_at=now(),reviewed_by=auth.uid(),review_note='Cancellation approved' where id=r.event_id;
else
update public.stroked_v5_events set payload=r.payload,reviewed_at=now(),reviewed_by=auth.uid(),review_note='Changes approved' where id=r.event_id;
end if;
end if;
update public.stroked_v53_requests set status=p_decision,reviewed_at=now(),reviewed_by=auth.uid(),review_note=left(coalesce(p_note,''),500) where id=p_id;
return true; end; $function$;
revoke all on function public.stroked_v53_review_request(uuid,text,text) from public;
grant execute on function public.stroked_v53_review_request(uuid,text,text) to anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.stroked_v53_save_profile(p_profile jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ begin
if auth.uid() is null then raise exception 'Sign in required'; end if;
if jsonb_typeof(p_profile)<>'object' or length(p_profile::text)>2500 then raise exception 'Invalid profile'; end if;
if length(trim(coalesce(p_profile->>'organization','')))<2 then raise exception 'Enter your organization name'; end if;
if coalesce(p_profile->>'public_email','')<>'' and coalesce(p_profile->>'public_email','') !~ '^[^ @]+@[^ @]+\.[^ @]+$' then raise exception 'Invalid email'; end if;
insert into public.stroked_v53_profiles(user_id,organization,city,region,public_email,website)
values(auth.uid(),left(trim(p_profile->>'organization'),100),left(trim(coalesce(p_profile->>'city','')),80),left(trim(coalesce(p_profile->>'region','')),80),left(trim(coalesce(p_profile->>'public_email','')),160),left(trim(coalesce(p_profile->>'website','')),300))
on conflict(user_id) do update set organization=excluded.organization,city=excluded.city,region=excluded.region,public_email=excluded.public_email,website=excluded.website,updated_at=now();
return true; end; $function$;
revoke all on function public.stroked_v53_save_profile(jsonb) from public;
grant execute on function public.stroked_v53_save_profile(jsonb) to anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.stroked_v54_my_rsvp(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'response',r.response,
    'guests',r.guests
  )
  FROM public.stroked_v54_rsvps r
  WHERE r.event_id = p_event_id
    AND r.user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.stroked_v5_events e
      WHERE e.id = r.event_id
        AND e.status = 'approved'
    );
$function$;
revoke all on function public.stroked_v54_my_rsvp(uuid) from public;
grant execute on function public.stroked_v54_my_rsvp(uuid) to anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.stroked_v54_public_organizer(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'organization',p.organization,
    'city',p.city,
    'region',p.region,
    'public_email',p.public_email,
    'website',p.website
  )
  FROM public.stroked_v5_events e
  JOIN public.stroked_v53_profiles p
    ON p.user_id = e.created_by
  WHERE e.id = p_event_id
    AND e.status = 'approved';
$function$;
revoke all on function public.stroked_v54_public_organizer(uuid) from public;
grant execute on function public.stroked_v54_public_organizer(uuid) to anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.stroked_v54_public_rsvp_counts()
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'event_id',e.id,
    'going',count(r.user_id)
      FILTER (WHERE r.response = 'going'),
    'interested',count(r.user_id)
      FILTER (WHERE r.response = 'interested'),
    'guests',coalesce(
      sum(r.guests) FILTER (WHERE r.response = 'going'),0
    ),
    'attendees',coalesce(
      sum(1+r.guests) FILTER (WHERE r.response = 'going'),0
    )
  )
  FROM public.stroked_v5_events e
  LEFT JOIN public.stroked_v54_rsvps r
    ON r.event_id = e.id
  WHERE e.status = 'approved'
  GROUP BY e.id
  ORDER BY e.id
  LIMIT 2000;
$function$;
revoke all on function public.stroked_v54_public_rsvp_counts() from public;
grant execute on function public.stroked_v54_public_rsvp_counts() to anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.stroked_v54_save_rsvp(p_event_id uuid, p_response text, p_guests integer DEFAULT 0)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in to RSVP';
  END IF;

  IF p_response NOT IN ('going','interested','not_going') THEN
    RAISE EXCEPTION 'Invalid RSVP';
  END IF;

  IF p_guests IS NULL OR p_guests < 0 OR p_guests > 10 THEN
    RAISE EXCEPTION 'Guests must be between 0 and 10';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.stroked_v5_events e
    WHERE e.id = p_event_id
      AND e.status = 'approved'
      AND (e.payload->>'date') ~ '^\d{4}-\d{2}-\d{2}$'
      AND (e.payload->>'date') >= current_date::text
  ) THEN
    RAISE EXCEPTION 'This event is not available for RSVP';
  END IF;

  IF p_response = 'not_going' THEN
    DELETE FROM public.stroked_v54_rsvps
    WHERE event_id = p_event_id
      AND user_id = auth.uid();
  ELSE
    INSERT INTO public.stroked_v54_rsvps(
      event_id,user_id,response,guests
    )
    VALUES (
      p_event_id,
      auth.uid(),
      p_response,
      CASE WHEN p_response = 'going' THEN p_guests ELSE 0 END
    )
    ON CONFLICT (event_id,user_id)
    DO UPDATE SET
      response = excluded.response,
      guests = excluded.guests,
      updated_at = now();
  END IF;

  RETURN true;
END;
$function$;
revoke all on function public.stroked_v54_save_rsvp(uuid,text,integer) from public;
grant execute on function public.stroked_v54_save_rsvp(uuid,text,integer) to anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.stroked_v5_admin_events()
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not public.stroked_v5_is_admin() then
    raise exception 'Administrator only';
  end if;

  return query select jsonb_build_object(
    'id',e.id,'payload',e.payload,'status',e.status,
    'created_at',e.created_at,'review_note',e.review_note
  )
  from public.stroked_v5_events e
  order by case when e.status='pending' then 0 else 1 end,
    e.created_at desc limit 500;
end;
$function$;
revoke all on function public.stroked_v5_admin_events() from public;
grant execute on function public.stroked_v5_admin_events() to anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.stroked_v5_is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select auth.uid() is not null and exists (
    select 1 from public.event_admins where user_id = auth.uid()
  );
$function$;
revoke all on function public.stroked_v5_is_admin() from public;
grant execute on function public.stroked_v5_is_admin() to anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.stroked_v5_my_events()
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;

  return query select jsonb_build_object(
    'id',e.id,'payload',e.payload,'status',e.status,
    'created_at',e.created_at,'review_note',e.review_note
  )
  from public.stroked_v5_events e
  where e.created_by = auth.uid()
  order by e.created_at desc limit 250;
end;
$function$;
revoke all on function public.stroked_v5_my_events() from public;
grant execute on function public.stroked_v5_my_events() to anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.stroked_v5_public_events()
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'id',e.id,'payload',e.payload,'created_at',e.created_at
  )
  from public.stroked_v5_events e
  where e.status = 'approved'
  order by e.created_at desc limit 2000;
$function$;
revoke all on function public.stroked_v5_public_events() from public;
grant execute on function public.stroked_v5_public_events() to anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.stroked_v5_review(p_id uuid, p_decision text, p_note text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not public.stroked_v5_is_admin() then
    raise exception 'Administrator only';
  end if;

  if p_decision not in ('approved','rejected') then
    raise exception 'Decision must be approved or rejected';
  end if;

  update public.stroked_v5_events
  set status = p_decision,
      reviewed_at = now(),
      reviewed_by = auth.uid(),
      review_note = left(coalesce(p_note,''),500)
  where id = p_id and status = 'pending';

  return found;
end;
$function$;
revoke all on function public.stroked_v5_review(uuid,text,text) from public;
grant execute on function public.stroked_v5_review(uuid,text,text) to anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.stroked_v5_submit(p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in before submitting an event';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or length(p_payload::text) > 12000 then
    raise exception 'Invalid event details';
  end if;

  if length(trim(coalesce(p_payload->>'name',''))) not between 3 and 90
     or length(trim(coalesce(p_payload->>'club',''))) not between 2 and 80
     or length(trim(coalesce(p_payload->>'province',''))) not between 2 and 50
     or length(trim(coalesce(p_payload->>'city',''))) not between 2 and 70
     or coalesce(p_payload->>'date','') !~ '^\d{4}-\d{2}-\d{2}$'
     or jsonb_typeof(p_payload->'categories') <> 'array'
     or jsonb_array_length(p_payload->'categories') < 1 then
    raise exception 'Complete the required event fields';
  end if;

  perform (p_payload->>'date')::date;

  if (p_payload->>'date')::date < current_date - 1
     or (p_payload->>'date')::date > current_date + 1095 then
    raise exception 'Event date must be between yesterday and three years ahead';
  end if;

  insert into public.stroked_v5_events(created_by,payload)
    values (auth.uid(),p_payload) returning id into v_id;

  return v_id;
end;
$function$;
revoke all on function public.stroked_v5_submit(jsonb) from public;
grant execute on function public.stroked_v5_submit(jsonb) to anon,authenticated,service_role;
-- Unused pre-V5 RPCs remain in the real project; the transition must close every overload.
create function public.submit_event(text) returns uuid language sql security definer as $$select gen_random_uuid()$$;
create function public.review_event(uuid,text) returns void language plpgsql security definer as $$begin return;end$$;
grant execute on function public.submit_event(text),public.review_event(uuid,text) to authenticated;
