begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
-- Claims grant event-scoped management after an MFA-protected administrator review.
-- Original submission ownership, event IDs, media objects, RSVPs and follows stay intact.
create schema stroked_claims;
revoke all on schema stroked_claims from public,anon,authenticated;
create table stroked_claims.requests(
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.stroked_v5_events(id) on delete cascade,
 claimant_id uuid not null references auth.users(id) on delete cascade,
 contact_name text not null,organization text not null,organizer_role text not null,
 official_url text not null,explanation text not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected','withdrawn','revoked')),
 created_at timestamptz not null default now(),reviewed_at timestamptz,
 reviewed_by uuid references auth.users(id),review_note text not null default '',verification_note text not null default ''
);
create unique index stroked_claim_pending_unique on stroked_claims.requests(event_id,claimant_id) where status='pending';
create index stroked_claim_claimant_date on stroked_claims.requests(claimant_id,created_at desc);
create index stroked_claim_event_status on stroked_claims.requests(event_id,status);
create index stroked_claim_reviewer on stroked_claims.requests(reviewed_by);
create table stroked_claims.managers(
 event_id uuid primary key references public.stroked_v5_events(id) on delete cascade,
 manager_id uuid not null references auth.users(id) on delete cascade,
 claim_id uuid not null unique references stroked_claims.requests(id) on delete cascade,
 assigned_at timestamptz not null default now()
);
create index stroked_claim_manager on stroked_claims.managers(manager_id);
alter table stroked_claims.requests enable row level security;
alter table stroked_claims.managers enable row level security;
revoke all on stroked_claims.requests,stroked_claims.managers from public,anon,authenticated;
grant usage on schema stroked_claims to service_role;
grant all on stroked_claims.requests,stroked_claims.managers to service_role;

-- Private helpers are not executable by API roles. Privileged RPCs check their caller.
create function stroked_claims.can_manage(p_event_id uuid,p_user_id uuid) returns boolean
language sql stable set search_path='' as $$
 select exists(select 1 from public.stroked_v5_events e where e.id=p_event_id and
 (e.created_by=p_user_id or exists(select 1 from stroked_claims.managers m where m.event_id=e.id and m.manager_id=p_user_id)));
$$;
create function stroked_claims.claimable(p_event_id uuid) returns boolean
language sql stable set search_path='' as $$
 select exists(select 1 from public.stroked_v5_events e where e.id=p_event_id and e.status='approved'
 and exists(select 1 from public.event_admins a where a.user_id=e.created_by)
 and not exists(select 1 from stroked_claims.managers m where m.event_id=e.id));
$$;
create function stroked_claims.update_image(p_event_id uuid,p_path text) returns text
language plpgsql stable set search_path='' as $$
declare u uuid:=stroked_live_v55.verified_uid();
begin
 if not stroked_claims.can_manage(p_event_id,u) then raise exception 'Event not found or not yours' using errcode='42501';end if;
 if coalesce(p_path,'')='' then return '';end if;
 if p_path ~ '^production/[a-f0-9-]{36}/[a-f0-9-]{36}[.](jpg|png|webp)$'
 and exists(select 1 from storage.objects where bucket_id='stroked-event-images' and name=p_path)
 and exists(select 1 from public.stroked_v5_events e where e.id=p_event_id and
 (e.payload->>'cover'=p_path or coalesce(e.payload->'photos','[]') ? p_path or
 exists(select 1 from jsonb_array_elements(coalesce(e.payload->'sponsors','[]')) s where s->>'logo'=p_path))) then return p_path;end if;
 return stroked_live_v55.valid_event_image(p_path);
end $$;

CREATE OR REPLACE FUNCTION stroked_claims.valid_update(p_event_id uuid, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$declare result jsonb;photos jsonb:='[]';v text;s jsonb;items jsonb:='[]';begin
 result:=stroked_live_v55.valid_payload_before_images(p);
 if jsonb_typeof(coalesce(p->'photos','[]')) is distinct from 'array' then raise exception 'Invalid event gallery';end if;
 if jsonb_array_length(coalesce(p->'photos','[]'))>6 then raise exception 'Choose up to six event photos';end if;
 for v in select jsonb_array_elements_text(coalesce(p->'photos','[]')) loop photos:=photos||jsonb_build_array(stroked_claims.update_image(p_event_id,v));end loop;
 for s in select value from jsonb_array_elements(coalesce(p->'sponsors','[]')) loop items:=items||jsonb_build_array(jsonb_build_object('name',s->>'name','contribution',left(coalesce(s->>'contribution',''),220),'link',left(coalesce(s->>'link',''),300),'logo',stroked_claims.update_image(p_event_id,s->>'logo')));end loop;
 return result||jsonb_build_object('cover',stroked_claims.update_image(p_event_id,p->>'cover'),'photos',photos,'sponsors',items);
 end$function$;

create function stroked_claims.submit(p_event_id uuid,p_details jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_live_v55.require_organizer();e public.stroked_v5_events%rowtype;v uuid;k text;
begin
 -- Serialize submissions per member and with reviews for this event.
 perform 1 from auth.users where id=u for update;
 select * into e from public.stroked_v5_events where id=p_event_id for update;
 if not found or not stroked_claims.claimable(p_event_id) then raise exception 'This event is not available to claim. Contact info@stroked.ca for help.';end if;
 if e.created_by=u then raise exception 'This event is already in your My Events.';end if;
 if p_details is null or jsonb_typeof(p_details) is distinct from 'object' or length(p_details::text)>4000 then raise exception 'Complete the organizer claim details';end if;
 for k in select unnest(array['contact_name','organization','organizer_role']) loop
  if jsonb_typeof(p_details->k) is distinct from 'string' or length(trim(p_details->>k)) not between 2 and 120 then raise exception 'Enter your name, organization and role';end if;
 end loop;
 if jsonb_typeof(p_details->'official_url') is distinct from 'string' or length(p_details->>'official_url')>500 or trim(p_details->>'official_url') !~ '^https://[^[:space:]<>]+$' then raise exception 'Enter a secure official website or club page';end if;
 if jsonb_typeof(p_details->'explanation') is distinct from 'string' or length(trim(p_details->>'explanation')) not between 20 and 1200 then raise exception 'Explain your organizer role and how Stroked can verify it (20–1200 characters)';end if;
 select id into v from stroked_claims.requests where event_id=p_event_id and claimant_id=u and status='pending';
 if v is not null then return v;end if;
 if (select count(*) from stroked_claims.requests where claimant_id=u and status='pending')>=3 or
 (select count(*) from stroked_claims.requests where claimant_id=u and created_at>now()-interval '24 hours')>=10 then raise exception 'You have reached the claim request limit. Wait for a review or contact info@stroked.ca.';end if;
 insert into stroked_claims.requests(event_id,claimant_id,contact_name,organization,organizer_role,official_url,explanation)
 values(p_event_id,u,trim(p_details->>'contact_name'),trim(p_details->>'organization'),trim(p_details->>'organizer_role'),trim(p_details->>'official_url'),trim(p_details->>'explanation')) returning id into v;
 return v;
end $$;
create function stroked_claims.mine() returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=stroked_live_v55.verified_uid();begin
 return query select jsonb_build_object('id',r.id,'event_id',r.event_id,'event_name',e.payload->>'name','status',r.status,'created_at',r.created_at,'review_note',r.review_note)
 from stroked_claims.requests r join public.stroked_v5_events e on e.id=r.event_id where r.claimant_id=u order by r.created_at desc limit 100;
end $$;
create function stroked_claims.admin_list() returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform stroked_live_v55.verified_uid();if not stroked_live_v55.is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
 return query select jsonb_build_object('id',r.id,'event_id',r.event_id,'event_name',e.payload->>'name','event_club',e.payload->>'club','event_date',e.payload->>'date',
 'official_event_contact',e.payload->>'organizerContact','event_details',e.payload->>'details','contact_name',r.contact_name,'organization',r.organization,'organizer_role',r.organizer_role,
 'official_url',r.official_url,'explanation',r.explanation,'verified_email',u.email,'email_confirmed',u.email_confirmed_at is not null,'blocked',b.user_id is not null,
 'status',r.status,'created_at',r.created_at,'review_note',r.review_note,'verification_note',r.verification_note)
 from stroked_claims.requests r join public.stroked_v5_events e on e.id=r.event_id join auth.users u on u.id=r.claimant_id
 left join stroked_live_v55.member_blocks b on b.user_id=u.id
 order by case r.status when 'pending' then 0 when 'approved' then 1 else 2 end,r.created_at desc limit 250;
end $$;
create function stroked_claims.withdraw(p_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_live_v55.verified_uid();begin
 update stroked_claims.requests set status='withdrawn',reviewed_at=now(),review_note='Withdrawn by applicant' where id=p_id and claimant_id=u and status='pending';return found;
end $$;
create function stroked_claims.review(p_id uuid,p_decision text,p_note text,p_verified boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare r stroked_claims.requests%rowtype;e public.stroked_v5_events%rowtype;
begin
 perform stroked_live_v55.verified_uid();if not stroked_live_v55.is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
 if p_decision is null or p_decision not in ('approved','rejected','revoked') then raise exception 'Choose a valid claim decision';end if;
 if length(trim(coalesce(p_note,''))) not between 10 and 1000 then raise exception 'Record a review reason or verification method (10–1000 characters)';end if;
 select * into r from stroked_claims.requests where id=p_id;
 if not found then return false;end if;
 -- Always lock event before claim, matching submission and competing approvals.
 select * into e from public.stroked_v5_events where id=r.event_id for update;
 select * into r from stroked_claims.requests where id=p_id for update;
 if p_decision='revoked' then
  if r.status<>'approved' then return false;end if;
  delete from stroked_claims.managers where event_id=r.event_id and claim_id=r.id;
  update stroked_claims.requests set status='revoked',reviewed_at=now(),reviewed_by=auth.uid(),review_note=trim(p_note) where id=r.id;
  update public.stroked_v53_requests set status='rejected',reviewed_at=now(),reviewed_by=auth.uid(),review_note='Organizer management access was removed. Contact Stroked.' where event_id=r.event_id and created_by=r.claimant_id and status='pending';
  return true;
 end if;
 if r.status<>'pending' then return false;end if;
 if p_decision='approved' then
  if p_verified is distinct from true then raise exception 'Verify the organizer through an independently published official contact before approval';end if;
  if not stroked_claims.claimable(r.event_id) then raise exception 'This event already has a manager or is no longer available';end if;
  if not exists(select 1 from auth.users u join stroked_live_v55.accounts a on a.user_id=u.id where u.id=r.claimant_id and u.email_confirmed_at is not null and a.account_type='organizer'
    and not exists(select 1 from stroked_live_v55.member_blocks b where b.user_id=u.id)) then raise exception 'The applicant needs an active, verified organizer account';end if;
  insert into stroked_claims.managers(event_id,manager_id,claim_id) values(r.event_id,r.claimant_id,r.id);
  update stroked_claims.requests set status='approved',reviewed_at=now(),reviewed_by=auth.uid(),review_note='Approved. This listing is now in your My Events.',verification_note=trim(p_note) where id=r.id;
  update stroked_claims.requests set status='rejected',reviewed_at=now(),reviewed_by=auth.uid(),review_note='Another verified organizer was approved to manage this event. Contact Stroked if this is incorrect.' where event_id=r.event_id and status='pending' and id<>r.id;
 else
  update stroked_claims.requests set status='rejected',reviewed_at=now(),reviewed_by=auth.uid(),review_note=trim(p_note) where id=r.id;
 end if;
 return true;
end $$;

-- Managed events use the same organizer change requests and administrator approval flow.
CREATE OR REPLACE FUNCTION stroked_live_v55.my_events()
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=stroked_live_v55.verified_uid();
begin
  return query select jsonb_build_object('id',e.id,'payload',e.payload,'created_at',e.created_at,'status',e.status,'review_note',e.review_note,'counts',stroked_live_v55.counts(e.id)) from public.stroked_v5_events e where stroked_claims.can_manage(e.id,u) order by created_at desc limit 250;
end $function$;
CREATE OR REPLACE FUNCTION stroked_live_v55.request_change(p_event_id uuid, p_payload jsonb, p_action text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=stroked_live_v55.require_organizer();e public.stroked_v5_events%rowtype;p jsonb;v uuid;
begin
  if p_action is null or p_action not in ('edit','cancel') then raise exception 'Invalid request type';end if;
  select * into e from public.stroked_v5_events where id=p_event_id and stroked_claims.can_manage(id,u) for update;
  if not found then raise exception 'Event not found or not yours' using errcode='42501';end if;
  p:=case when p_action='edit' then stroked_claims.valid_update(p_event_id,p_payload) else e.payload end;
  if exists(select 1 from public.stroked_v53_requests where event_id=e.id and status='pending') then raise exception 'This event already has a pending request';end if;
  insert into public.stroked_v53_requests(event_id,created_by,payload,base_payload,action) values(e.id,u,p,e.payload,p_action) returning id into v;
  return v;
end $function$;
CREATE OR REPLACE FUNCTION stroked_live_v55.review_request(p_id uuid, p_decision text, p_note text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.stroked_v53_requests%rowtype;e public.stroked_v5_events%rowtype;
begin
  perform stroked_live_v55.verified_uid();if not stroked_live_v55.is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
  if p_decision is null or p_decision not in ('approved','rejected') then raise exception 'Invalid review decision';end if;
  select * into r from public.stroked_v53_requests where id=p_id and status='pending' for update;
  if not found then return false;end if;
  select * into e from public.stroked_v5_events where id=r.event_id for update;
  if p_decision='approved' then
    if not stroked_claims.can_manage(r.event_id,r.created_by) or exists(select 1 from stroked_live_v55.member_blocks where user_id=r.created_by) then raise exception 'The applicant no longer manages this event. Reject this request.';end if;
    if r.base_payload<>e.payload then raise exception 'The event changed after this request. Reject it and ask the organizer to resubmit.';end if;
    update public.stroked_v5_events set payload=case when r.action='cancel' then jsonb_set(e.payload,'{status}','"Cancelled"') else stroked_live_v55.valid_payload(r.payload) end,
      status=case when r.action='cancel' and e.status<>'approved' then 'rejected' else 'approved' end,
      reviewed_at=now(),reviewed_by=auth.uid(),review_note=left(coalesce(p_note,''),500) where id=r.event_id;
  end if;
  update public.stroked_v53_requests set status=p_decision,reviewed_at=now(),reviewed_by=auth.uid(),review_note=left(coalesce(p_note,''),500) where id=p_id;
  return true;
end $function$;
CREATE OR REPLACE FUNCTION stroked_live_v55.public_events()
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
select jsonb_build_object(
  'id', e.id, 'payload', e.payload, 'created_at', e.created_at,
  'claimable',stroked_claims.claimable(e.id),'organizer_managed',m.manager_id is not null,
  'counts', stroked_live_v55.counts(e.id),
  'organizer', jsonb_build_object(
    'organization', coalesce(nullif(trim(e.payload->>'club'), ''), p.organization),
    'city', coalesce(nullif(trim(e.payload->>'city'), ''), p.city),
    'region', coalesce(nullif(trim(e.payload->>'province'), ''), p.region),
    'public_email', case when lower(trim(e.payload->>'club')) = lower(trim(p.organization)) then p.public_email else null end,
    'website', case
      when lower(trim(e.payload->>'club')) = lower(trim(p.organization)) then p.website
      when e.payload->>'organizerContact' ~ '^https?://[^[:space:]]+$' then e.payload->>'organizerContact'
      else null end
  )
)
from public.stroked_v5_events e
left join stroked_claims.managers m on m.event_id=e.id
left join public.stroked_v53_profiles p on p.user_id=coalesce(m.manager_id,e.created_by)
where e.status = 'approved'
order by e.created_at desc
limit 2000;
$function$;

revoke all on all functions in schema stroked_claims from public,anon,authenticated;
grant usage on schema stroked_claims to authenticated;
create function public.stroked_live_v55_submit_event_claim(p_event_id uuid,p_details jsonb) returns uuid language sql set search_path='' as $$select stroked_claims.submit(p_event_id,p_details);$$;
revoke all on function public.stroked_live_v55_submit_event_claim(uuid,jsonb) from public,anon;
grant execute on function public.stroked_live_v55_submit_event_claim(uuid,jsonb),stroked_claims.submit(uuid,jsonb) to authenticated;
create function public.stroked_live_v55_my_event_claims() returns setof jsonb language sql set search_path='' as $$select * from stroked_claims.mine();$$;
revoke all on function public.stroked_live_v55_my_event_claims() from public,anon;
grant execute on function public.stroked_live_v55_my_event_claims(),stroked_claims.mine() to authenticated;
create function public.stroked_live_v55_admin_event_claims() returns setof jsonb language sql set search_path='' as $$select * from stroked_claims.admin_list();$$;
revoke all on function public.stroked_live_v55_admin_event_claims() from public,anon;
grant execute on function public.stroked_live_v55_admin_event_claims(),stroked_claims.admin_list() to authenticated;
create function public.stroked_live_v55_withdraw_event_claim(p_id uuid) returns boolean language sql set search_path='' as $$select stroked_claims.withdraw(p_id);$$;
revoke all on function public.stroked_live_v55_withdraw_event_claim(uuid) from public,anon;
grant execute on function public.stroked_live_v55_withdraw_event_claim(uuid),stroked_claims.withdraw(uuid) to authenticated;
create function public.stroked_live_v55_review_event_claim(p_id uuid,p_decision text,p_note text,p_verified boolean default false) returns boolean language sql set search_path='' as $$select stroked_claims.review(p_id,p_decision,p_note,p_verified);$$;
revoke all on function public.stroked_live_v55_review_event_claim(uuid,text,text,boolean) from public,anon;
grant execute on function public.stroked_live_v55_review_event_claim(uuid,text,text,boolean),stroked_claims.review(uuid,text,text,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
