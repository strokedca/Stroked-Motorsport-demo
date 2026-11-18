insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('stroked-event-images','stroked-event-images',false,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create function stroked_live_v55.can_upload_event_image(p_name text) returns boolean language plpgsql stable security definer set search_path='' as $$declare u uuid;begin
 if exists(select 1 from stroked_live_v55.member_blocks where user_id=auth.uid()) then return false;end if;
 u:=stroked_live_v55.require_organizer();
 return p_name ~ ('^production/'||u::text||'/[a-f0-9-]{36}[.](jpg|png|webp)$') and (select count(*)<250 from storage.objects where bucket_id='stroked-event-images' and split_part(name,'/',2)=u::text);
 exception when insufficient_privilege then return false;end$$;
create function stroked_live_v55.can_read_event_image(p_name text) returns boolean language sql stable security definer set search_path='' as $$select
 (auth.uid() is not null and not exists(select 1 from stroked_live_v55.member_blocks where user_id=auth.uid()) and (split_part(p_name,'/',2)=auth.uid()::text or stroked_live_v55.is_admin())) or exists(select 1 from public.stroked_v5_events e where e.status='approved' and (e.payload->>'cover'=p_name or coalesce(e.payload->'photos','[]') ? p_name or exists(select 1 from jsonb_array_elements(coalesce(e.payload->'sponsors','[]')) s where s->>'logo'=p_name)))$$;
revoke all on function stroked_live_v55.can_upload_event_image(text),stroked_live_v55.can_read_event_image(text) from public;
grant execute on function stroked_live_v55.can_upload_event_image(text) to authenticated;
grant execute on function stroked_live_v55.can_read_event_image(text) to anon,authenticated;
create policy stroked_event_image_insert on storage.objects for insert to authenticated with check(bucket_id='stroked-event-images' and stroked_live_v55.can_upload_event_image(name));
create policy stroked_event_image_read on storage.objects for select to anon,authenticated using(bucket_id='stroked-event-images' and stroked_live_v55.can_read_event_image(name));
create function stroked_live_v55.valid_event_image(p_path text) returns text language plpgsql stable security definer set search_path='' as $$declare u uuid;begin
 if coalesce(p_path,'')='' then return '';end if;
 u:=stroked_live_v55.verified_uid();
 if p_path !~ '^production/[a-f0-9-]{36}/[a-f0-9-]{36}[.](jpg|png|webp)$' or not exists(select 1 from storage.objects where bucket_id='stroked-event-images' and name=p_path) or (split_part(p_path,'/',2)<>u::text and not stroked_live_v55.is_admin()) then raise exception 'Choose an image uploaded by your organizer account';end if;
 return p_path;end$$;
-- Extend the existing validator without changing its event checks or approval rules.
alter function stroked_live_v55.valid_payload(jsonb) rename to valid_payload_before_images;
create function stroked_live_v55.valid_payload(p jsonb) returns jsonb language plpgsql set search_path='' as $$declare result jsonb;photos jsonb:='[]';v text;s jsonb;items jsonb:='[]';begin
 result:=stroked_live_v55.valid_payload_before_images(p);
 if jsonb_typeof(coalesce(p->'photos','[]')) is distinct from 'array' then raise exception 'Invalid event gallery';end if;
 if jsonb_array_length(coalesce(p->'photos','[]'))>6 then raise exception 'Choose up to six event photos';end if;
 for v in select jsonb_array_elements_text(coalesce(p->'photos','[]')) loop photos:=photos||jsonb_build_array(stroked_live_v55.valid_event_image(v));end loop;
 for s in select value from jsonb_array_elements(coalesce(p->'sponsors','[]')) loop items:=items||jsonb_build_array(jsonb_build_object('name',s->>'name','contribution',left(coalesce(s->>'contribution',''),220),'link',left(coalesce(s->>'link',''),300),'logo',stroked_live_v55.valid_event_image(s->>'logo')));end loop;
 return result||jsonb_build_object('cover',stroked_live_v55.valid_event_image(p->>'cover'),'photos',photos,'sponsors',items);
 end$$;
revoke all on function stroked_live_v55.valid_payload_before_images(jsonb),stroked_live_v55.valid_event_image(text),stroked_live_v55.valid_payload(jsonb) from public,anon;
grant execute on function stroked_live_v55.valid_event_image(text),stroked_live_v55.valid_payload(jsonb),stroked_live_v55.valid_payload_before_images(jsonb) to authenticated;
notify pgrst,'reload schema';
