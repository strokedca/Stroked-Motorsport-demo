begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
-- Preserve the installed image-validation wrapper; extend its underlying field validator.
CREATE OR REPLACE FUNCTION stroked_live_v55.valid_payload_before_images(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare result jsonb;cats jsonb;sponsors jsonb:='[]';s jsonb;d date;last_day date;
begin
  if p is null or jsonb_typeof(p) is distinct from 'object' or length(p::text)>12000 then raise exception 'Invalid event details';end if;
  if length(trim(coalesce(p->>'name',''))) not between 3 and 90
     or length(trim(coalesce(p->>'club',''))) not between 2 and 80
     or length(trim(coalesce(p->>'province',''))) not between 2 and 50
     or length(trim(coalesce(p->>'city',''))) not between 2 and 70
     or coalesce(p->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Complete the required event fields';end if;
  d:=(p->>'date')::date;
  if coalesce(p->>'endDate','')<>'' and p->>'endDate' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Invalid end date';end if;
  last_day:=coalesce(nullif(p->>'endDate',''),p->>'date')::date;
  if last_day<d or last_day>d+366 then raise exception 'End date must be on or after the start, within one year';end if;
  if last_day<(now() at time zone 'America/Halifax')::date-1 or d>(now() at time zone 'America/Halifax')::date+1095 then raise exception 'Event must end no earlier than yesterday and start within three years';end if;
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
  result:=jsonb_build_object('name',trim(p->>'name'),'club',trim(p->>'club'),'date',p->>'date','endDate',coalesce(nullif(p->>'endDate',''),''),'categories',cats,'province',case when lower(regexp_replace(p->>'province','[.[:space:]_-]','','g')) in ('pei','princeedwardisland') then 'PEI' else trim(p->>'province') end,'city',trim(p->>'city'),'sponsors',sponsors,'status',coalesce(p->>'status','Scheduled'));
  select result||jsonb_object_agg(k,left(trim(coalesce(p->>k,'')),n)) into result from (values('state',50),('time',5),('rain',10),('startLocation',180),('endLocation',180),('registration',5),('ksu',5),('organizerContact',220),('stops',700),('food',400),('details',600)) f(k,n);
  return result;
end $function$;
CREATE OR REPLACE FUNCTION stroked_live_v55.save_rsvp(p_event_id uuid, p_response text, p_guests integer DEFAULT 0)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=stroked_live_v55.verified_uid();e public.stroked_v5_events%rowtype;
begin
  if p_response is null or p_response not in ('going','interested','not_going') then raise exception 'Invalid RSVP';end if;
  if p_guests is null or p_guests not between 0 and 10 then raise exception 'Guests must be between 0 and 10';end if;
  -- A person may remove their own RSVP even after cancellation or the event date.
  if p_response='not_going' then delete from public.stroked_v54_rsvps where event_id=p_event_id and user_id=u;return true;end if;
  select * into e from public.stroked_v5_events where id=p_event_id for share;
  if not found or e.status<>'approved' or coalesce(e.payload->>'status','Scheduled')='Cancelled'
    or coalesce(e.payload->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or coalesce(nullif(e.payload->>'endDate',''),e.payload->>'date')::date<(now() at time zone 'America/Halifax')::date then raise exception 'This event is not available for RSVP';end if;
  insert into public.stroked_v54_rsvps(event_id,user_id,response,guests) values(p_event_id,u,p_response,case when p_response='going' then p_guests else 0 end)
  on conflict(event_id,user_id) do update set response=excluded.response,guests=excluded.guests,updated_at=now();return true;
end $function$;
-- Approved public listings only. Ranges checked against organizer sources on 2026-11-25.
update public.stroked_v5_events e set payload=jsonb_set(e.payload,'{endDate}',to_jsonb(v.end_day))
from (values
('Motorcycle & Powersport Show — Abbotsford','Moto Canada','2027-01-15','2027-01-17'),
('2027 Atlantic Groomer Demo & Powersports Show','Snowmobile NB','2027-01-29','2027-01-30'),
('Motorcycle & Powersport Show — Calgary','Moto Canada','2027-02-05','2027-02-07'),
('Red Dirt Ride 2027','North Cape Coastal Drive','2027-02-05','2027-02-07'),
('Motorcycle & Powersport Show — Toronto','Moto Canada','2027-02-19','2027-02-21'),
('Maritime Snowmobile Championship Racing 2027','Maritime Snowmobile Championship Racing (MSCR)','2027-02-19','2027-02-21'),
('Motorcycle & Powersport Show — Montréal','Moto Canada','2027-02-26','2027-02-28'),
('Radical Speed Sport','Radical Speed Sport','2027-04-16','2027-04-18'),
('Atlantic Truck Show','Atlantic Provinces Trucking Association / Marketplace Events','2027-05-07','2027-05-08'),
('4th Annual Eastern Canadian IMRG Celebration 2027','IMRG Canada (Indian Motorcycle Riders Group of Canada)','2027-06-30','2027-07-04'),
('Atlantic Nationals Automotive Extravaganza','Atlantic Nationals','2027-07-07','2027-07-11')
) v(name,club,start_day,end_day)
where e.payload->>'name'=v.name and e.payload->>'club'=v.club and e.status='approved' and e.payload->>'date'=v.start_day;
update public.stroked_v5_events set payload=jsonb_set(payload,'{province}','"PEI"'::jsonb)
where status='approved' and payload->>'province'='Prince Edward Island';
notify pgrst,'reload schema';
commit;
