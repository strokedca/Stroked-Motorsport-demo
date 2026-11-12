-- Additive site promotions. Existing events, accounts, RSVPs and payments are untouched.
begin;
set local lock_timeout='5s';
create schema if not exists stroked_promotions;
revoke all on schema stroked_promotions from public,anon,authenticated;
create table if not exists stroked_promotions.promotions(
  id uuid primary key default gen_random_uuid(),
  environment text not null check(environment in ('production','testing')),
  payload jsonb not null check(jsonb_typeof(payload)='object'),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists site_promotions_environment on stroked_promotions.promotions(environment,updated_at desc);
create index if not exists site_promotions_creator on stroked_promotions.promotions(created_by);
alter table stroked_promotions.promotions enable row level security;
revoke all on stroked_promotions.promotions from public,anon,authenticated;

create or replace function stroked_promotions.is_admin(p_environment text) returns boolean
language sql stable security definer set search_path='' as $$
select exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null)
  and case p_environment
    when 'production' then exists(select 1 from public.event_admins where user_id=auth.uid())
    when 'testing' then exists(select 1 from stroked_v55_testing.admins where user_id=auth.uid())
    else false end;
$$;
create or replace function stroked_promotions.require_admin(p_environment text) returns uuid
language plpgsql stable security definer set search_path='' as $$
begin
  if not stroked_promotions.is_admin(p_environment) then raise exception 'Administrator only' using errcode='42501';end if;
  return auth.uid();
end $$;

create or replace function stroked_promotions.media_path(p_path text,p_environment text) returns text
language plpgsql stable set search_path='' as $$
begin
  if coalesce(p_path,'')='' then return '';end if;
  if p_environment not in ('production','testing') or p_path !~ ('^'||p_environment||'/[a-f0-9-]{36}[.](jpg|png|webp)$')
    or not exists(select 1 from storage.objects where bucket_id='stroked-promotion-images' and name=p_path) then
    raise exception 'Choose an uploaded promotion image';
  end if;
  return p_path;
end $$;

create or replace function stroked_promotions.valid_payload(p jsonb,p_environment text) returns jsonb
language plpgsql set search_path='' as $$
declare result jsonb;k text;n integer;start_on date;end_on date;linked uuid;photos jsonb:='[]';photo text;
begin
  if p is null or jsonb_typeof(p) is distinct from 'object' or length(p::text)>18000 then raise exception 'Invalid promotion details';end if;
  if length(trim(coalesce(p->>'title',''))) not between 3 and 100 then raise exception 'Enter a promotion title of 3 to 100 characters';end if;
  if coalesce(p->>'kind','') not in ('Local event','Charity event','Community announcement') then raise exception 'Choose a valid promotion type';end if;
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
  return result||jsonb_build_object('event_id',coalesce(linked::text,''),'start_date',start_on::text,'end_date',coalesce(end_on::text,''),
    'cover',stroked_promotions.media_path(p->>'cover',p_environment),'photos',photos,'sponsor_image',stroked_promotions.media_path(p->>'sponsor_image',p_environment));
end $$;

create or replace function stroked_promotions.list_public(p_environment text) returns setof jsonb
language sql stable security definer set search_path='' as $$
select jsonb_build_object('id',p.id,'payload',p.payload) from stroked_promotions.promotions p
where p.environment=p_environment and (p.payload->>'active')::boolean
  and (p.payload->>'start_date')::date<=(now() at time zone 'America/Halifax')::date
  and (nullif(p.payload->>'end_date','') is null or nullif(p.payload->>'end_date','')::date>=(now() at time zone 'America/Halifax')::date)
  and (p.payload->>'event_id'='' or
    (p_environment='production' and exists(select 1 from public.stroked_v5_events e where e.id=nullif(p.payload->>'event_id','')::uuid and e.status='approved')) or
    (p_environment='testing' and exists(select 1 from stroked_v55_testing.events e where e.id=nullif(p.payload->>'event_id','')::uuid and e.status='approved')))
order by (p.payload->>'featured')::boolean desc,p.updated_at desc limit 100;
$$;
create or replace function stroked_promotions.list_admin(p_environment text) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  perform stroked_promotions.require_admin(p_environment);
  return query select jsonb_build_object('id',id,'payload',payload,'updated_at',updated_at) from stroked_promotions.promotions where environment=p_environment order by updated_at desc limit 500;
end $$;
create or replace function stroked_promotions.save(p_environment text,p_payload jsonb,p_id uuid default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_promotions.require_admin(p_environment);p jsonb:=stroked_promotions.valid_payload(p_payload,p_environment);result uuid;
begin
  if p_id is null then
    insert into stroked_promotions.promotions(environment,payload,created_by) values(p_environment,p,u) returning id into result;
  else
    update stroked_promotions.promotions set payload=p,updated_at=now() where id=p_id and environment=p_environment returning id into result;
    if not found then raise exception 'Promotion not found in this environment';end if;
  end if;
  return result;
end $$;

create or replace function public.stroked_live_v55_public_promotions() returns setof jsonb language sql stable security invoker set search_path='' as $$select * from stroked_promotions.list_public('production');$$;
create or replace function public.stroked_live_v55_admin_promotions() returns setof jsonb language sql stable security invoker set search_path='' as $$select * from stroked_promotions.list_admin('production');$$;
create or replace function public.stroked_live_v55_save_promotion(p_payload jsonb,p_id uuid default null) returns uuid language sql security invoker set search_path='' as $$select stroked_promotions.save('production',p_payload,p_id);$$;
create or replace function public.stroked_v55_public_promotions() returns setof jsonb language sql stable security invoker set search_path='' as $$select * from stroked_promotions.list_public('testing');$$;
create or replace function public.stroked_v55_admin_promotions() returns setof jsonb language sql stable security invoker set search_path='' as $$select * from stroked_promotions.list_admin('testing');$$;
create or replace function public.stroked_v55_save_promotion(p_payload jsonb,p_id uuid default null) returns uuid language sql security invoker set search_path='' as $$select stroked_promotions.save('testing',p_payload,p_id);$$;
revoke all on all functions in schema stroked_promotions from public,anon,authenticated;
grant usage on schema stroked_promotions to anon,authenticated,service_role;
grant execute on function stroked_promotions.list_public(text) to anon,authenticated;
grant execute on function stroked_promotions.is_admin(text),stroked_promotions.list_admin(text),stroked_promotions.save(text,jsonb,uuid) to authenticated;
revoke all on function public.stroked_live_v55_public_promotions(),public.stroked_live_v55_admin_promotions(),public.stroked_live_v55_save_promotion(jsonb,uuid),public.stroked_v55_public_promotions(),public.stroked_v55_admin_promotions(),public.stroked_v55_save_promotion(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.stroked_live_v55_public_promotions(),public.stroked_v55_public_promotions() to anon,authenticated;
grant execute on function public.stroked_live_v55_admin_promotions(),public.stroked_live_v55_save_promotion(jsonb,uuid),public.stroked_v55_admin_promotions(),public.stroked_v55_save_promotion(jsonb,uuid) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('stroked-promotion-images','stroked-promotion-images',true,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
drop policy if exists stroked_promotion_image_insert on storage.objects;
create policy stroked_promotion_image_insert on storage.objects for insert to authenticated
with check(bucket_id='stroked-promotion-images' and stroked_promotions.is_admin(split_part(name,'/',1)) and name ~ '^(production|testing)/[a-f0-9-]{36}[.](jpg|png|webp)$');
commit;
