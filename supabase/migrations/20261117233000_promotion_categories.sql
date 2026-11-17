create or replace function stroked_promotions.valid_payload(p jsonb,p_environment text) returns jsonb
language plpgsql set search_path='' as $$
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
    if jsonb_array_length(p->'categories')>5 then raise exception 'Choose up to five categories';end if;
    if exists(select 1 from jsonb_array_elements(p->'categories') c where jsonb_typeof(c) <> 'string' or c #>> '{}' not in ('Motorcycles','ATVs / Off-road','Classic cars','Snowmobiles','Motocross / Dirt track')) then raise exception 'Choose valid promotion categories';end if;
  end if;
  result:=result||jsonb_build_object('categories',coalesce(p->'categories','[]'::jsonb));
  return result||jsonb_build_object('event_id',coalesce(linked::text,''),'start_date',start_on::text,'end_date',coalesce(end_on::text,''),
    'cover',stroked_promotions.media_path(p->>'cover',p_environment),'photos',photos,'sponsor_image',stroked_promotions.media_path(p->>'sponsor_image',p_environment));
end $$;

