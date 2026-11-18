create schema if not exists stroked_alerts;
revoke all on schema stroked_alerts from public,anon,authenticated;
create table stroked_alerts.settings(id boolean primary key default true check(id),email_ready boolean not null default false);
insert into stroked_alerts.settings values(true,false);
create table stroked_alerts.preferences(user_id uuid references auth.users(id) on delete cascade,event_id uuid references public.stroked_v5_events(id) on delete cascade,email_updates boolean not null default false,primary key(user_id,event_id));
create table stroked_alerts.outbox(id uuid primary key default gen_random_uuid(),user_id uuid references auth.users(id) on delete cascade,event_id uuid references public.stroked_v5_events(id) on delete cascade,kind text not null,payload jsonb not null,status text not null default 'pending' check(status in ('pending','processing','sent','cancelled','failed')),attempts int not null default 0,created_at timestamptz not null default now(),available_at timestamptz not null default now(),provider_id text,last_error text);
alter table stroked_alerts.settings enable row level security;
alter table stroked_alerts.preferences enable row level security;
alter table stroked_alerts.outbox enable row level security;
create index on stroked_alerts.outbox(status,available_at);
create function public.stroked_live_v55_notification_status() returns boolean language sql stable security definer set search_path='' as $$select email_ready from stroked_alerts.settings where id$$;
create function public.stroked_live_v55_alerts_my_rsvp(p_event_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare u uuid:=stroked_live_v55.verified_uid();r jsonb;begin r:=public.stroked_live_v55_my_rsvp(p_event_id);if r is null then return null;end if;return r||jsonb_build_object('email_updates',coalesce((select email_updates from stroked_alerts.preferences where user_id=u and event_id=p_event_id),false));end$$;
create function public.stroked_live_v55_alerts_save_rsvp(p_event_id uuid,p_response text,p_guests integer default 0,p_email_updates boolean default false) returns boolean language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_live_v55.verified_uid();e jsonb;previous public.stroked_v54_rsvps%rowtype;old_opt boolean;begin
 select * into previous from public.stroked_v54_rsvps where event_id=p_event_id and user_id=u;
 select email_updates into old_opt from stroked_alerts.preferences where event_id=p_event_id and user_id=u;
 perform stroked_live_v55.save_rsvp(p_event_id,p_response,p_guests);
 if p_response='not_going' then delete from stroked_alerts.preferences where event_id=p_event_id and user_id=u;update stroked_alerts.outbox set status='cancelled' where event_id=p_event_id and user_id=u and status in ('pending','processing');return true;end if;
 if p_email_updates and not public.stroked_live_v55_notification_status() then raise exception 'Email alerts are not available yet';end if;
 insert into stroked_alerts.preferences values(u,p_event_id,coalesce(p_email_updates,false)) on conflict(user_id,event_id) do update set email_updates=excluded.email_updates;
 if not coalesce(p_email_updates,false) then update stroked_alerts.outbox set status='cancelled' where event_id=p_event_id and user_id=u and status in ('pending','processing');
 elsif previous.response is distinct from p_response or previous.guests is distinct from (case when p_response='going' then p_guests else 0 end) or not coalesce(old_opt,false) then
 select payload into e from public.stroked_v5_events where id=p_event_id;
 insert into stroked_alerts.outbox(user_id,event_id,kind,payload) values(u,p_event_id,'confirmation',jsonb_build_object('event',e,'response',p_response,'guests',case when p_response='going' then p_guests else 0 end));end if;return true;end$$;
create function stroked_alerts.event_changed() returns trigger language plpgsql security definer set search_path='' as $$begin
 if old.status='approved' and (new.payload is distinct from old.payload or new.status is distinct from old.status) then
 insert into stroked_alerts.outbox(user_id,event_id,kind,payload) select p.user_id,new.id,'event_update',jsonb_build_object('event',new.payload,'unavailable',new.status<>'approved') from stroked_alerts.preferences p join public.stroked_v54_rsvps r on r.user_id=p.user_id and r.event_id=p.event_id where p.event_id=new.id and p.email_updates and r.response in ('going','interested') and coalesce(old.payload->>'date','')>=((now() at time zone 'America/Halifax')::date)::text;
 end if;return new;end$$;
create trigger stroked_email_event_changed after update on public.stroked_v5_events for each row execute function stroked_alerts.event_changed();
-- Worker authentication is separate from browser authentication; only service_role can call these functions.
select vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'stroked_alert_worker');
create function public.stroked_alert_worker_authorize(p_token text) returns boolean language sql stable security definer set search_path='' as $$select coalesce(length(p_token)=64 and p_token=(select decrypted_secret from vault.decrypted_secrets where name='stroked_alert_worker'),false)$$;
create function public.stroked_alert_worker_ready(p_ready boolean) returns void language sql security definer set search_path='' as $$update stroked_alerts.settings set email_ready=p_ready where id$$;
create function public.stroked_alert_worker_claim() returns setof jsonb language plpgsql security definer set search_path='' as $$begin
 update stroked_alerts.outbox o set status='cancelled' where status in ('pending','processing') and (not exists(select 1 from stroked_alerts.preferences p where p.user_id=o.user_id and p.event_id=o.event_id and p.email_updates) or not exists(select 1 from public.stroked_v54_rsvps r where r.user_id=o.user_id and r.event_id=o.event_id));
 return query with candidates as(select id from stroked_alerts.outbox where status in ('pending','processing') and available_at<=now() and attempts<5 and created_at>now()-interval '20 hours' order by created_at for update skip locked limit 10),claimed as(update stroked_alerts.outbox o set status='processing',attempts=attempts+1,available_at=now()+interval '5 minutes' from candidates c where c.id=o.id returning o.*) select jsonb_build_object('id',o.id,'event_id',o.event_id,'kind',o.kind,'payload',o.payload,'email',u.email) from claimed o join auth.users u on u.id=o.user_id where u.email_confirmed_at is not null;
 update stroked_alerts.outbox set status='failed',last_error='Retry window ended' where status in ('pending','processing') and (attempts>=5 or created_at<=now()-interval '20 hours') and available_at<=now();end$$;
create function public.stroked_alert_worker_ack(p_id uuid,p_provider_id text,p_error text default null) returns void language sql security definer set search_path='' as $$update stroked_alerts.outbox set status=case when p_error is null then 'sent' when attempts>=5 then 'failed' else 'pending' end,provider_id=left(p_provider_id,200),last_error=left(p_error,200),available_at=now()+interval '5 minutes' where id=p_id and status='processing'$$;
revoke all on all functions in schema stroked_alerts from public,anon,authenticated;
revoke all on function public.stroked_live_v55_notification_status() from public;
grant execute on function public.stroked_live_v55_notification_status() to anon,authenticated;
revoke all on function public.stroked_live_v55_alerts_my_rsvp(uuid),public.stroked_live_v55_alerts_save_rsvp(uuid,text,integer,boolean) from public,anon;
grant execute on function public.stroked_live_v55_alerts_my_rsvp(uuid),public.stroked_live_v55_alerts_save_rsvp(uuid,text,integer,boolean) to authenticated;
revoke all on function public.stroked_alert_worker_authorize(text),public.stroked_alert_worker_ready(boolean),public.stroked_alert_worker_claim(),public.stroked_alert_worker_ack(uuid,text,text) from public,anon,authenticated;
grant execute on function public.stroked_alert_worker_authorize(text),public.stroked_alert_worker_ready(boolean),public.stroked_alert_worker_claim(),public.stroked_alert_worker_ack(uuid,text,text) to service_role;
