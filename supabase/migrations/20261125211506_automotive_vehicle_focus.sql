begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
-- Optional interests live inside the existing event payload. Keep the historic Classic cars
-- marker only for existing exact-match email/advertising preferences; do not broaden opt-ins.
create or replace function stroked_live_v55.with_vehicle_focus(cleaned jsonb,p jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare cats jsonb:=coalesce(cleaned->'categories','[]');focus jsonb:='[]';v text;automotive boolean;
begin
  automotive:=cats ? 'Cars & trucks' or cats ? 'Classic cars';
  if p ? 'vehicleFocus' then
    if jsonb_typeof(p->'vehicleFocus') is distinct from 'array' then raise exception 'Choose valid Cars & Trucks interests';end if;
    if jsonb_array_length(p->'vehicleFocus')>4 or exists(select 1 from jsonb_array_elements_text(p->'vehicleFocus') x where x is null or x not in ('Classic & Antique','Modern','Custom & Modified','Commercial & Heavy Vehicles')) then raise exception 'Choose valid Cars & Trucks interests';end if;
    for v in select jsonb_array_elements_text(p->'vehicleFocus') loop
      if not focus ? v then focus:=focus||jsonb_build_array(v);end if;
    end loop;
  elsif cats ? 'Classic cars' then focus:='["Classic & Antique"]'::jsonb;
  end if;
  cats:=cats-'Classic cars';
  if automotive then
    if not cats ? 'Cars & trucks' then cats:=cats||'["Cars & trucks"]'::jsonb;end if;
    if focus ? 'Classic & Antique' then cats:=cats||'["Classic cars"]'::jsonb;end if;
  else focus:='[]'::jsonb;
  end if;
  return cleaned||jsonb_build_object('categories',cats,'vehicleFocus',focus);
end $$;
revoke all on function stroked_live_v55.with_vehicle_focus(jsonb,jsonb) from public,anon;
grant execute on function stroked_live_v55.with_vehicle_focus(jsonb,jsonb) to authenticated,service_role;

-- Extend the field validators while leaving the installed upload-ownership wrapper intact.
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
  return stroked_live_v55.with_vehicle_focus(result,p);
end $function$;

CREATE OR REPLACE FUNCTION stroked_v55_testing.valid_payload(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
  return stroked_live_v55.with_vehicle_focus(result,p);
end $function$;

-- Automotive placement shares the umbrella category; historic classic placements stay scoped.
CREATE OR REPLACE FUNCTION stroked_promotions.valid_payload(p jsonb, p_environment text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare result jsonb;k text;n integer;start_on date;end_on date;linked uuid;photos jsonb:='[]';photo text;
begin
  if p is null or jsonb_typeof(p) is distinct from 'object' or length(p::text)>18000 then raise exception 'Invalid promotion details';end if;
  if length(trim(coalesce(p->>'title',''))) not between 3 and 100 then raise exception 'Enter a promotion title of 3 to 100 characters';end if;
  if coalesce(p->>'kind','') not in ('Local event','Charity event','Community announcement','Business advertisement') then raise exception 'Choose a valid promotion type';end if;
  for k in select unnest(array['featured','enhanced','spotlight','active']) loop
    if p ? k and jsonb_typeof(p->k) is distinct from 'boolean' then raise exception 'Invalid promotion option';end if;
  end loop;
  result:=jsonb_build_object('title',trim(p->>'title'),'kind',p->>'kind','featured',coalesce((p->>'featured')::boolean,false),'enhanced',coalesce((p->>'enhanced')::boolean,false),'spotlight',coalesce((p->>'spotlight')::boolean,false),'active',coalesce((p->>'active')::boolean,true));
  for k,n in select * from (values('tagline',160),('description',1600),('link',500),('sponsor_name',120),('sponsor_link',500)) f(key,max_length) loop
    if length(coalesce(p->>k,''))>n then raise exception 'Promotion field exceeds the permitted length';end if;
    result:=result||jsonb_build_object(k,trim(coalesce(p->>k,'')));
  end loop;
  for k in select unnest(array['link','sponsor_link']) loop
    if result->>k<>'' and result->>k !~ '^https://[^[:space:]]+$' then raise exception 'Use a secure https website link';end if;
  end loop;
  if (result->>'spotlight')::boolean and result->>'sponsor_name'='' then raise exception 'Enter a sponsor name for Sponsor Spotlight';end if;
  if coalesce(p->>'start_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Choose a valid start date';end if;
  start_on:=(p->>'start_date')::date;
  if coalesce(p->>'end_date','')<>'' then
    if p->>'end_date' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Choose a valid end date';end if;
    end_on:=(p->>'end_date')::date;
    if end_on<start_on then raise exception 'The end date must be on or after the start date';end if;
  end if;
  if coalesce(p->>'event_id','')<>'' then
    linked:=(p->>'event_id')::uuid;
    if p_environment='production' then
      if not exists(select 1 from public.stroked_v5_events where id=linked and (status='approved' or not (result->>'active')::boolean)) then raise exception 'Choose an approved event';end if;
    else
      if not exists(select 1 from stroked_v55_testing.events where id=linked and (status='approved' or not (result->>'active')::boolean)) then raise exception 'Choose an approved testing event';end if;
    end if;
  end if;
  if jsonb_typeof(coalesce(p->'photos','[]'::jsonb)) is distinct from 'array' then raise exception 'Invalid photo gallery';end if;
  if jsonb_array_length(coalesce(p->'photos','[]'::jsonb))>6 then raise exception 'Choose up to six gallery photos';end if;
  for photo in select jsonb_array_elements_text(coalesce(p->'photos','[]'::jsonb)) loop
    photos:=photos||jsonb_build_array(stroked_promotions.media_path(photo,p_environment));
  end loop;
  if p ? 'categories' then
    if jsonb_typeof(p->'categories') is distinct from 'array' then raise exception 'Invalid promotion categories';end if;
    if jsonb_array_length(p->'categories')>6 then raise exception 'Choose up to six categories';end if;
    if exists(select 1 from jsonb_array_elements(p->'categories') c where jsonb_typeof(c) <> 'string' or c #>> '{}' not in ('Motorcycles','Cars & trucks','ATVs / Off-road','Classic cars','Snowmobiles','Motocross / Dirt track')) then raise exception 'Choose valid promotion categories';end if;
  end if;
  result:=result||jsonb_build_object('categories',coalesce(p->'categories','[]'::jsonb));
  return result||jsonb_build_object('event_id',coalesce(linked::text,''),'start_date',start_on::text,'end_date',coalesce(end_on::text,''),
    'cover',stroked_promotions.media_path(p->>'cover',p_environment),'photos',photos,'sponsor_image',stroked_promotions.media_path(p->>'sponsor_image',p_environment));
end $function$;

-- Metadata-only backfill: do not send followers an event-change email. This trigger only
-- enqueues messages. The migration transaction and table lock restore it on any rollback.
do $$begin
  if (select tgenabled from pg_trigger where tgrelid='public.stroked_v5_events'::regclass and tgname='stroked_email_event_changed') is distinct from 'O' then raise exception 'Review email trigger state before taxonomy backfill';end if;
end $$;
alter table public.stroked_v5_events disable trigger stroked_email_event_changed;
update public.stroked_v5_events set payload=stroked_live_v55.with_vehicle_focus(payload,payload)
where payload->'categories' ?| array['Classic cars','Cars & trucks'];
-- Match source-backed public listings by name, organizer and start date, not generated IDs.
with focus(name,club,event_day,interests) as (values
 ('Atlantic Truck Show','Atlantic Provinces Trucking Association / Marketplace Events','2027-05-07','["Commercial & Heavy Vehicles"]'::jsonb),
 ('Atlantic Nationals Automotive Extravaganza','Atlantic Nationals','2027-07-07','["Classic & Antique","Custom & Modified"]'::jsonb),
 ('Radical Speed Sport','Radical Speed Sport','2027-04-16','["Classic & Antique","Custom & Modified"]'::jsonb)
)
update public.stroked_v5_events e set payload=stroked_live_v55.with_vehicle_focus(e.payload,e.payload||jsonb_build_object('vehicleFocus',f.interests))
from focus f where e.status='approved' and e.payload->>'name'=f.name and e.payload->>'club'=f.club and e.payload->>'date'=f.event_day;
alter table public.stroked_v5_events enable trigger stroked_email_event_changed;
update stroked_v55_testing.events set payload=stroked_live_v55.with_vehicle_focus(payload,payload)
where payload->'categories' ?| array['Classic cars','Cars & trucks'];
commit;
