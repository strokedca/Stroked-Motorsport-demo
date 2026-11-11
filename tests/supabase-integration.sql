-- Runs against the installed TESTING API. Every fixture and write is rolled back.
-- No emails, passwords or persistent test identities are created.
begin;
do $$
declare
  organizer uuid:=gen_random_uuid();rider uuid:=gen_random_uuid();other_user uuid:=gen_random_uuid();
  reviewer uuid:=gen_random_uuid();unverified uuid:=gen_random_uuid();
  event_id uuid;request_id uuid;cancel_id uuid;value jsonb;payload jsonb;denied boolean;
begin
  insert into auth.users(id,aud,role,email,email_confirmed_at,raw_user_meta_data)
  values
    (organizer,'authenticated','authenticated','v55-organizer-'||organizer||'@example.invalid',now(),'{"account_type":"organizer"}'),
    (rider,'authenticated','authenticated','v55-rider-'||rider||'@example.invalid',now(),'{"account_type":"rider","is_admin":true}'),
    (other_user,'authenticated','authenticated','v55-other-'||other_user||'@example.invalid',now(),'{"account_type":"organizer"}'),
    (reviewer,'authenticated','authenticated','v55-reviewer-'||reviewer||'@example.invalid',now(),'{"account_type":"rider"}'),
    (unverified,'authenticated','authenticated','v55-unverified-'||unverified||'@example.invalid',null,'{}');
  insert into stroked_v55_testing.admins(user_id) values(reviewer);
  payload:=jsonb_build_object('name','V5.5 rollback test ride','club','V5.5 Test Club','province','PEI','city','Charlottetown','date',(current_date+7)::text,'categories',jsonb_build_array('Motorcycles'),'status','Scheduled');

  perform set_config('request.jwt.claim.sub',rider::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rider,'role','authenticated')::text,true);
  set local role authenticated;
  value:=public.stroked_v55_my_account();
  if value->>'account_type'<>'rider' or (value->>'is_admin')::boolean then raise exception 'Rider permission bootstrap failed';end if;
  denied:=false;begin perform public.stroked_v55_submit(payload);exception when insufficient_privilege then denied:=true;end;
  if not denied then raise exception 'Rider could submit an event';end if;
  denied:=false;begin perform public.stroked_v55_admin_events();exception when insufficient_privilege then denied:=true;end;
  if not denied then raise exception 'Rider could read administrator queue';end if;
  denied:=false;begin perform 1 from stroked_v55_testing.accounts;exception when insufficient_privilege then denied:=true;end;
  if not denied then raise exception 'Direct private table access allowed';end if;

  perform set_config('request.jwt.claim.sub',unverified::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',unverified,'role','authenticated')::text,true);
  denied:=false;begin perform public.stroked_v55_my_account();exception when insufficient_privilege then denied:=true;end;
  if not denied then raise exception 'Unverified identity accepted';end if;

  perform set_config('request.jwt.claim.sub',organizer::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',organizer,'role','authenticated')::text,true);
  event_id:=public.stroked_v55_submit(payload);
  if exists(select 1 from public.stroked_v55_public_events() p where p->>'id'=event_id::text) then raise exception 'Pending event exposed';end if;
  if not public.stroked_v55_save_profile('{"organization":"V5.5 Test Club","public_email":"public@example.invalid","website":"https://example.invalid"}') then raise exception 'Profile save failed';end if;

  perform set_config('request.jwt.claim.sub',other_user::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',other_user,'role','authenticated')::text,true);
  denied:=false;begin perform public.stroked_v55_request_change(event_id,payload,'edit');exception when insufficient_privilege then denied:=true;end;
  if not denied then raise exception 'Other organizer could change event';end if;
  denied:=false;begin perform public.stroked_v55_review(event_id,'approved','');exception when insufficient_privilege then denied:=true;end;
  if not denied then raise exception 'Other organizer could approve event';end if;

  perform set_config('request.jwt.claim.sub',reviewer::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',reviewer,'role','authenticated')::text,true);
  if not public.stroked_v55_review(event_id,'approved','Rollback test') then raise exception 'Approval failed';end if;
  if public.stroked_v55_review(event_id,'approved','') then raise exception 'Duplicate approval accepted';end if;

  perform set_config('request.jwt.claim.sub',rider::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rider,'role','authenticated')::text,true);
  perform public.stroked_v55_save_rsvp(event_id,'going',2);
  perform public.stroked_v55_save_rsvp(event_id,'going',2);
  select p->'counts' into value from public.stroked_v55_public_events() p where p->>'id'=event_id::text;
  if value<>'{"going":1,"guests":2,"interested":0}'::jsonb then raise exception 'Duplicate RSVP or totals error: %',value;end if;
  if public.stroked_v55_my_rsvp(event_id)<>'{"response":"going","guests":2}'::jsonb then raise exception 'Own RSVP reload failed';end if;
  perform public.stroked_v55_save_rsvp(event_id,'interested',8);
  if public.stroked_v55_my_rsvp(event_id)<>'{"response":"interested","guests":0}'::jsonb then raise exception 'Interested guests were not cleared';end if;
  perform public.stroked_v55_save_rsvp(event_id,'going',1);

  perform set_config('request.jwt.claim.sub',other_user::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',other_user,'role','authenticated')::text,true);
  if public.stroked_v55_my_rsvp(event_id) is not null then raise exception 'Other account could read rider RSVP';end if;
  perform public.stroked_v55_save_rsvp(event_id,'going',3);
  select p->'counts' into value from public.stroked_v55_public_events() p where p->>'id'=event_id::text;
  if value<>'{"going":2,"guests":4,"interested":0}'::jsonb then raise exception 'Multi-account totals error';end if;

  perform set_config('request.jwt.claim.sub',organizer::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',organizer,'role','authenticated')::text,true);
  request_id:=public.stroked_v55_request_change(event_id,jsonb_set(payload,'{name}','"Updated rollback test ride"'),'edit');
  select p->'payload' into value from public.stroked_v55_public_events() p where p->>'id'=event_id::text;
  if value->>'name'<>'V5.5 rollback test ride' then raise exception 'Unapproved change exposed';end if;

  perform set_config('request.jwt.claim.sub',reviewer::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',reviewer,'role','authenticated')::text,true);
  if not public.stroked_v55_review_request(request_id,'approved','') then raise exception 'Change approval failed';end if;
  select p->'payload' into value from public.stroked_v55_public_events() p where p->>'id'=event_id::text;
  if value->>'name'<>'Updated rollback test ride' then raise exception 'Approved change not applied';end if;

  perform set_config('request.jwt.claim.sub',organizer::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',organizer,'role','authenticated')::text,true);
  cancel_id:=public.stroked_v55_request_change(event_id,payload,'cancel');
  perform set_config('request.jwt.claim.sub',reviewer::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',reviewer,'role','authenticated')::text,true);
  perform public.stroked_v55_review_request(cancel_id,'approved','');
  select p->'payload' into value from public.stroked_v55_public_events() p where p->>'id'=event_id::text;
  if value->>'status'<>'Cancelled' then raise exception 'Cancellation disappeared instead of marking listing';end if;

  perform set_config('request.jwt.claim.sub',rider::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rider,'role','authenticated')::text,true);
  denied:=false;begin perform public.stroked_v55_save_rsvp(event_id,'going',0);exception when others then if sqlerrm like '%not available%' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'Cancelled event accepted RSVP';end if;
  perform public.stroked_v55_save_rsvp(event_id,'not_going',0);
  if public.stroked_v55_my_rsvp(event_id) is not null then raise exception 'RSVP removal after cancellation failed';end if;
  reset role;
end $$;
rollback;
select jsonb_build_object('server_workflow_assertions_passed',true,'fixtures_rolled_back',not exists(select 1 from auth.users where email like 'v55-%@example.invalid'),
 'live_event_hash',(select md5(coalesce(jsonb_agg(to_jsonb(e) order by id)::text,'')) from public.stroked_v5_events e),
 'live_rsvps',(select count(*) from public.stroked_v54_rsvps),
 'live_admins',(select count(*) from public.event_admins)) as test_result;
