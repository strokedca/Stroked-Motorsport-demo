-- Per-account quotas are enforced in the database, including legacy live APIs.
create index if not exists stroked_events_submission_quota on public.stroked_v5_events(created_by,created_at desc);
create index if not exists stroked_testing_events_submission_quota on stroked_v55_testing.events(created_by,created_at desc);
create or replace function stroked_live_v55.enforce_event_quota(p_user uuid,p_environment text) returns void
language plpgsql security definer set search_path='' as $$
declare hourly integer;daily integer;pending integer;
begin
 -- Serialize submissions by the same account so parallel requests cannot evade a quota.
 perform 1 from auth.users where id=p_user for update;
 if not found then raise exception 'Sign in with a verified email address' using errcode='42501';end if;
 if p_environment='production' then
  if stroked_live_v55.is_admin() then return;end if;
  select count(*) filter(where created_at>now()-interval '1 hour'),count(*) filter(where created_at>now()-interval '24 hours'),count(*) filter(where status='pending')
   into hourly,daily,pending from public.stroked_v5_events where created_by=p_user;
 elsif p_environment='testing' then
  if stroked_v55_testing.is_admin() then return;end if;
  select count(*) filter(where created_at>now()-interval '1 hour'),count(*) filter(where created_at>now()-interval '24 hours'),count(*) filter(where status='pending')
   into hourly,daily,pending from stroked_v55_testing.events where created_by=p_user;
 else raise exception 'Invalid event environment';end if;
 if hourly>=10 then raise exception 'Event submission limit reached: 10 per hour. Please try later.' using errcode='P0001';end if;
 if daily>=30 then raise exception 'Event submission limit reached: 30 per day. Please try tomorrow.' using errcode='P0001';end if;
 if pending>=20 then raise exception 'You have 20 events awaiting review. Please wait for approval before submitting more.' using errcode='P0001';end if;
end $$;
revoke all on function stroked_live_v55.enforce_event_quota(uuid,text) from public,anon,authenticated;

create or replace function stroked_live_v55.submit(p_payload jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_live_v55.require_organizer();v uuid;p jsonb:=stroked_live_v55.valid_payload(p_payload);
begin
 perform stroked_live_v55.enforce_event_quota(u,'production');
 insert into public.stroked_v5_events(created_by,payload) values(u,p) returning id into v;
 return v;
end $$;
create or replace function public.stroked_v55_submit(p_payload jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_v55_testing.require_organizer();v uuid;p jsonb:=stroked_v55_testing.valid_payload(p_payload);
begin
 perform stroked_live_v55.enforce_event_quota(u,'testing');
 insert into stroked_v55_testing.events(created_by,payload) values(u,p) returning id into v;
 return v;
end $$;
revoke all on function public.stroked_v55_submit(jsonb) from public,anon;
grant execute on function public.stroked_v55_submit(jsonb) to authenticated;
notify pgrst,'reload schema';
