create table stroked_alerts.subscriptions (
 user_id uuid primary key references auth.users(id) on delete cascade,
 new_events boolean not null default false, follow_emails boolean not null default false, reminders boolean not null default false,
 regions jsonb not null default '["PEI"]', categories jsonb not null default '["Motorcycles"]', updated_at timestamptz not null default now()
);
create table stroked_alerts.event_follows(user_id uuid references auth.users(id) on delete cascade,event_id uuid references public.stroked_v5_events(id) on delete cascade,primary key(user_id,event_id));
create table stroked_alerts.organizer_follows(user_id uuid references auth.users(id) on delete cascade,organizer_key text not null,organizer_name text not null,primary key(user_id,organizer_key));
alter table stroked_alerts.subscriptions enable row level security;
alter table stroked_alerts.event_follows enable row level security;
alter table stroked_alerts.organizer_follows enable row level security;
revoke all on stroked_alerts.subscriptions,stroked_alerts.event_follows,stroked_alerts.organizer_follows from public,anon,authenticated;
alter table stroked_alerts.outbox add column dedupe_key text;
create unique index stroked_alert_dedupe on stroked_alerts.outbox(user_id,dedupe_key) where dedupe_key is not null;
create function stroked_alerts.organizer_key(p jsonb) returns text language sql immutable set search_path='' as $$select lower(trim(regexp_replace(coalesce(p->>'club',''),'[[:space:]]+',' ','g')))$$;
create function stroked_alerts.matches(s stroked_alerts.subscriptions,p jsonb) returns boolean language sql immutable set search_path='' as $$select (s.regions ? 'All Canada' or s.regions ? (p->>'province')) and exists(select 1 from jsonb_array_elements_text(coalesce(p->'categories','[]')) c where s.categories ? c)$$;
create function public.stroked_live_v55_my_alert_settings() returns jsonb language plpgsql stable security definer set search_path='' as $$declare u uuid:=stroked_live_v55.verified_uid();begin return jsonb_build_object(
 'settings',coalesce((select to_jsonb(s)-'user_id' from stroked_alerts.subscriptions s where user_id=u),'{}'),
 'events',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'name',e.payload->>'name','date',e.payload->>'date','available',e.status='approved')) from stroked_alerts.event_follows f join public.stroked_v5_events e on e.id=f.event_id where f.user_id=u),'[]'),
 'organizers',coalesce((select jsonb_agg(jsonb_build_object('key',organizer_key,'name',organizer_name)) from stroked_alerts.organizer_follows where user_id=u),'[]'));end$$;
create function public.stroked_live_v55_save_alert_settings(p_settings jsonb) returns boolean language plpgsql security definer set search_path='' as $$declare u uuid:=stroked_live_v55.verified_uid();k text;r jsonb;c jsonb;begin
 if p_settings is null or jsonb_typeof(p_settings)<>'object' or length(p_settings::text)>2000 then raise exception 'Invalid email settings';end if;
 for k in select unnest(array['new_events','follow_emails','reminders']) loop if jsonb_typeof(p_settings->k) is distinct from 'boolean' then raise exception 'Choose valid email options';end if;end loop;
 r:=p_settings->'regions';c:=p_settings->'categories';
 if jsonb_typeof(r) is distinct from 'array' or jsonb_typeof(c) is distinct from 'array' then raise exception 'Choose regions and categories';end if;
 if jsonb_array_length(r)>14 or jsonb_array_length(c)>6 or exists(select 1 from jsonb_array_elements_text(r) x where x is null or x not in ('All Canada','PEI','Nova Scotia','New Brunswick','Newfoundland and Labrador','Quebec','Ontario','Manitoba','Saskatchewan','Alberta','British Columbia','Yukon','Northwest Territories','Nunavut')) or exists(select 1 from jsonb_array_elements_text(c) x where x is null or x not in ('Motorcycles','ATVs / Off-road','Classic cars','Cars & trucks','Snowmobiles','Motocross / Dirt track')) then raise exception 'Choose valid Canadian regions and categories';end if;
 if (p_settings->>'new_events')::boolean and (jsonb_array_length(r)=0 or jsonb_array_length(c)=0) then raise exception 'Choose at least one region and category for new-event emails';end if;
 insert into stroked_alerts.subscriptions values(u,(p_settings->>'new_events')::boolean,(p_settings->>'follow_emails')::boolean,(p_settings->>'reminders')::boolean,r,c,now()) on conflict(user_id) do update set new_events=excluded.new_events,follow_emails=excluded.follow_emails,reminders=excluded.reminders,regions=excluded.regions,categories=excluded.categories,updated_at=now();return true;end$$;
create function public.stroked_live_v55_set_follow(p_event_id uuid,p_kind text,p_follow boolean) returns boolean language plpgsql security definer set search_path='' as $$declare u uuid:=stroked_live_v55.verified_uid();e public.stroked_v5_events%rowtype;begin
 if p_kind not in ('event','organizer') or p_kind is null or p_follow is null then raise exception 'Invalid follow choice';end if;
 select * into e from public.stroked_v5_events where id=p_event_id and status='approved';if not found then raise exception 'Approved event not found';end if;
 if p_kind='event' then if p_follow then insert into stroked_alerts.event_follows values(u,e.id) on conflict do nothing;else delete from stroked_alerts.event_follows where user_id=u and event_id=e.id;end if;
 else if length(stroked_alerts.organizer_key(e.payload))<2 then raise exception 'Organizer is not specified';end if;if p_follow then insert into stroked_alerts.organizer_follows values(u,stroked_alerts.organizer_key(e.payload),e.payload->>'club') on conflict do nothing;else delete from stroked_alerts.organizer_follows where user_id=u and organizer_key=stroked_alerts.organizer_key(e.payload);end if;end if;return true;end$$;
create function public.stroked_live_v55_unfollow(p_kind text,p_key text) returns boolean language plpgsql security definer set search_path='' as $$declare u uuid:=stroked_live_v55.verified_uid();begin
 if p_kind='event' then delete from stroked_alerts.event_follows where user_id=u and event_id=p_key::uuid;
 elsif p_kind='organizer' then delete from stroked_alerts.organizer_follows where user_id=u and organizer_key=p_key;
 else raise exception 'Invalid follow choice';end if;return true;end$$;
-- Eligibility is rechecked at delivery, so opting out or blocking cancels queued mail.
create function stroked_alerts.eligible(o stroked_alerts.outbox) returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from stroked_live_v55.member_blocks where user_id=o.user_id) and exists(select 1 from auth.users where id=o.user_id and email_confirmed_at is not null and deleted_at is null) and exists(
 select 1 from public.stroked_v5_events e left join stroked_alerts.subscriptions s on s.user_id=o.user_id where e.id=o.event_id and case
 when o.kind='confirmation' then exists(select 1 from stroked_alerts.preferences p join public.stroked_v54_rsvps r on r.user_id=p.user_id and r.event_id=p.event_id where p.user_id=o.user_id and p.event_id=e.id and p.email_updates and r.response=o.payload->>'response' and r.guests=coalesce((o.payload->>'guests')::int,0))
 when o.kind='event_update' then exists(select 1 from stroked_alerts.preferences p join public.stroked_v54_rsvps r on r.user_id=p.user_id and r.event_id=p.event_id where p.user_id=o.user_id and p.event_id=e.id and p.email_updates) or (coalesce(s.follow_emails,false) and (exists(select 1 from stroked_alerts.event_follows f where f.user_id=o.user_id and f.event_id=e.id) or exists(select 1 from stroked_alerts.organizer_follows f where f.user_id=o.user_id and f.organizer_key in (stroked_alerts.organizer_key(e.payload),o.payload->>'previous_organizer_key'))))
 when o.kind='new_event' then e.status='approved' and coalesce(e.payload->>'status','Scheduled')<>'Cancelled' and e.payload->>'date'>=((now() at time zone 'America/Halifax')::date)::text and ((coalesce(s.new_events,false) and stroked_alerts.matches(s,e.payload)) or (coalesce(s.follow_emails,false) and exists(select 1 from stroked_alerts.organizer_follows f where f.user_id=o.user_id and f.organizer_key=stroked_alerts.organizer_key(e.payload))))
 when o.kind='reminder' then e.status='approved' and coalesce(e.payload->>'status','Scheduled') not in ('Cancelled','Postponed') and e.payload->>'date'=o.payload->'event'->>'date' and e.payload->>'date'>((now() at time zone 'America/Halifax')::date)::text and coalesce(s.reminders,false) and (exists(select 1 from public.stroked_v54_rsvps r where r.user_id=o.user_id and r.event_id=e.id and r.response in ('going','interested')) or exists(select 1 from stroked_alerts.event_follows f where f.user_id=o.user_id and f.event_id=e.id))
 else false end);$$;
create or replace function stroked_alerts.event_changed() returns trigger language plpgsql security definer set search_path='' as $$declare fresh boolean;day text:=((now() at time zone 'America/Halifax')::date)::text;begin
 fresh:=new.status='approved' and (tg_op='INSERT' or old.status<>'approved');
 if fresh and new.payload->>'date'>=day and coalesce(new.payload->>'status','Scheduled')<>'Cancelled' and new.payload->>'province'<>'United States' then
 insert into stroked_alerts.outbox(user_id,event_id,kind,payload,dedupe_key) select s.user_id,new.id,'new_event',jsonb_build_object('event',new.payload),'new:'||new.id from stroked_alerts.subscriptions s where (s.new_events and stroked_alerts.matches(s,new.payload)) or (s.follow_emails and exists(select 1 from stroked_alerts.organizer_follows f where f.user_id=s.user_id and f.organizer_key=stroked_alerts.organizer_key(new.payload))) on conflict(user_id,dedupe_key) where dedupe_key is not null do nothing;
 elsif tg_op='UPDATE' and old.status='approved' and (new.payload is distinct from old.payload or new.status is distinct from old.status) and old.payload->>'date'>=day then
 update stroked_alerts.outbox set status='cancelled' where event_id=new.id and kind='event_update' and status='pending';
 insert into stroked_alerts.outbox(user_id,event_id,kind,payload,dedupe_key)
 select u,new.id,'event_update',jsonb_build_object('event',new.payload,'unavailable',new.status<>'approved','previous_organizer_key',stroked_alerts.organizer_key(old.payload)),'change:'||new.id||':'||md5(new.payload::text||new.status) from (
 select p.user_id u from stroked_alerts.preferences p join public.stroked_v54_rsvps r on r.user_id=p.user_id and r.event_id=p.event_id where p.event_id=new.id and p.email_updates
 union select f.user_id from stroked_alerts.event_follows f join stroked_alerts.subscriptions s on s.user_id=f.user_id where f.event_id=new.id and s.follow_emails
 union select f.user_id from stroked_alerts.organizer_follows f join stroked_alerts.subscriptions s on s.user_id=f.user_id where f.organizer_key in (stroked_alerts.organizer_key(new.payload),stroked_alerts.organizer_key(old.payload)) and s.follow_emails
 ) recipients on conflict(user_id,dedupe_key) where dedupe_key is not null do nothing;
 end if;return new;end$$;
drop trigger stroked_email_event_changed on public.stroked_v5_events;
create trigger stroked_email_event_changed after insert or update on public.stroked_v5_events for each row execute function stroked_alerts.event_changed();
create function stroked_alerts.enqueue_reminders(p_now timestamptz default now()) returns void language plpgsql security definer set search_path='' as $$declare tomorrow text:=((p_now at time zone 'America/Halifax')::date+1)::text;begin
 if (p_now at time zone 'America/Halifax')::time<'09:00' then return;end if;
 insert into stroked_alerts.outbox(user_id,event_id,kind,payload,dedupe_key)
 select s.user_id,e.id,'reminder',jsonb_build_object('event',e.payload),'reminder:'||e.id||':'||tomorrow from stroked_alerts.subscriptions s cross join public.stroked_v5_events e where s.reminders and e.status='approved' and e.payload->>'date'=tomorrow and coalesce(e.payload->>'status','Scheduled') not in ('Cancelled','Postponed') and (exists(select 1 from public.stroked_v54_rsvps r where r.user_id=s.user_id and r.event_id=e.id and r.response in ('going','interested')) or exists(select 1 from stroked_alerts.event_follows f where f.user_id=s.user_id and f.event_id=e.id)) on conflict(user_id,dedupe_key) where dedupe_key is not null do nothing;
 end$$;
create or replace function public.stroked_alert_worker_claim() returns setof jsonb language plpgsql security definer set search_path='' as $$begin
 perform stroked_alerts.enqueue_reminders();
 update stroked_alerts.outbox o set status='cancelled' where status in ('pending','processing') and not stroked_alerts.eligible(o);
 return query with candidates as(select id from stroked_alerts.outbox where status in ('pending','processing') and available_at<=now() and attempts<5 and created_at>now()-interval '20 hours' order by created_at for update skip locked limit 10),claimed as(update stroked_alerts.outbox o set status='processing',attempts=attempts+1,available_at=now()+interval '5 minutes' from candidates c where c.id=o.id returning o.*) select jsonb_build_object('id',o.id,'event_id',o.event_id,'kind',o.kind,'payload',o.payload,'email',u.email) from claimed o join auth.users u on u.id=o.user_id where u.email_confirmed_at is not null;
 update stroked_alerts.outbox set status='failed',last_error='Retry window ended' where status in ('pending','processing') and (attempts>=5 or created_at<=now()-interval '20 hours') and available_at<=now();end$$;
revoke all on all functions in schema stroked_alerts from public,anon,authenticated;
revoke all on function public.stroked_live_v55_my_alert_settings(),public.stroked_live_v55_save_alert_settings(jsonb),public.stroked_live_v55_set_follow(uuid,text,boolean),public.stroked_live_v55_unfollow(text,text) from public,anon;
grant execute on function public.stroked_live_v55_my_alert_settings(),public.stroked_live_v55_save_alert_settings(jsonb),public.stroked_live_v55_set_follow(uuid,text,boolean),public.stroked_live_v55_unfollow(text,text) to authenticated;
notify pgrst,'reload schema';
