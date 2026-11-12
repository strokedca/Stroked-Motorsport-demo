-- One-time promotion bookings. Browser URLs never establish payment success.
begin;
set local search_path='';
create schema if not exists stroked_payments;
revoke all on schema stroked_payments from public,anon,authenticated;
create table stroked_payments.settings(environment text primary key check(environment in ('production','testing')),enabled boolean not null default false);
insert into stroked_payments.settings(environment) values('production'),('testing');
create table stroked_payments.catalog(
 environment text not null references stroked_payments.settings,sku text not null,label text not null,
 kind text not null check(kind in ('event','business','tip')),duration integer not null,unit text not null check(unit in ('week','month','tip')),
 amount_cents integer not null check(amount_cents>=0),currency text not null default 'cad' check(currency='cad'),
 price_id text not null default '',payment_link_id text not null default '',payment_link text not null default '',
 primary key(environment,sku)
);
insert into stroked_payments.catalog(environment,sku,label,kind,duration,unit,amount_cents)
select e.environment,p.* from stroked_payments.settings e cross join (values
 ('featured_event_2','Featured Event','event',2,'week',1500),('featured_event_4','Featured Event','event',4,'week',2500),('featured_event_6','Featured Event','event',6,'week',3500),
 ('enhanced_event_2','Enhanced Event Page','event',2,'week',1000),('enhanced_event_4','Enhanced Event Page','event',4,'week',1500),('enhanced_event_6','Enhanced Event Page','event',6,'week',2000),
 ('sponsor_spotlight_2','Sponsor Spotlight','event',2,'week',1500),('sponsor_spotlight_4','Sponsor Spotlight','event',4,'week',2500),('sponsor_spotlight_6','Sponsor Spotlight','event',6,'week',3500),
 ('business_card_1','Business promotion card','business',1,'month',2500),('business_card_3','Business promotion card','business',3,'month',6500),('business_card_6','Business promotion card','business',6,'month',12000),
 ('featured_business_1','Featured business promotion','business',1,'month',5000),('featured_business_3','Featured business promotion','business',3,'month',13500),('featured_business_6','Featured business promotion','business',6,'month',25000),
 ('site_support_0','Voluntary site support','tip',0,'tip',0)
)p(sku,label,kind,duration,unit,amount_cents);
create table stroked_payments.bookings(
 id uuid primary key default gen_random_uuid(),environment text not null,sku text not null,
 user_id uuid not null references auth.users(id),event_id uuid,title text not null,website text not null default '',notes text not null default '',
 preferred_start date not null,amount_cents integer not null,currency text not null default 'cad',
 payment_status text not null default 'unpaid' check(payment_status in ('unpaid','paid','failed','review')),
 status text not null default 'awaiting_payment' check(status in ('awaiting_payment','awaiting_publication','published','payment_review')),
 stripe_session text unique,paid_at timestamptz,promotion_id uuid references stroked_promotions.promotions(id),starts_on date,ends_on date,
 created_at timestamptz not null default now(),foreign key(environment,sku) references stroked_payments.catalog(environment,sku)
);
create index payment_bookings_owner on stroked_payments.bookings(user_id,created_at desc);
create index payment_bookings_event on stroked_payments.bookings(event_id);
create index payment_bookings_promotion on stroked_payments.bookings(promotion_id);
create table stroked_payments.receipts(
 session_id text primary key,environment text not null,sku text not null,booking_id uuid references stroked_payments.bookings(id),
 payment_intent text,amount_cents integer not null,status text not null,created_at timestamptz not null default now(),
 foreign key(environment,sku) references stroked_payments.catalog(environment,sku)
);
create index payment_receipts_booking on stroked_payments.receipts(booking_id);
create index payment_receipts_intent on stroked_payments.receipts(payment_intent);
create table stroked_payments.processed_events(id text primary key,event_type text not null,processed_at timestamptz not null default now());
create table stroked_payments.reversals(payment_intent text primary key,reason text not null,created_at timestamptz not null default now());
alter table stroked_payments.settings enable row level security;
alter table stroked_payments.catalog enable row level security;
alter table stroked_payments.bookings enable row level security;
alter table stroked_payments.receipts enable row level security;
alter table stroked_payments.processed_events enable row level security;
alter table stroked_payments.reversals enable row level security;
revoke all on all tables in schema stroked_payments from public,anon,authenticated;
grant all on all tables in schema stroked_payments to service_role;

create function stroked_payments.require_user() returns uuid language plpgsql stable security definer set search_path='' as $$
begin if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Sign in with a verified email address' using errcode='42501';end if;return auth.uid();end $$;
create function stroked_payments.campaign_end(p_start date,p_count integer,p_unit text) returns date language sql immutable security invoker set search_path='' as $$select case when p_unit='week' then p_start+p_count*7-1 else (p_start+make_interval(months=>p_count))::date-1 end;$$;
create function stroked_payments.public_catalog(p_env text) returns setof jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('sku',c.sku,'label',c.label,'kind',c.kind,'duration',c.duration,'unit',c.unit,'amount_cents',c.amount_cents,'currency',c.currency,'ready',s.enabled and c.payment_link<>'') from stroked_payments.catalog c join stroked_payments.settings s on s.environment=c.environment where c.environment=p_env;
$$;
create function stroked_payments.create_booking(p_env text,p_sku text,p_details jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_payments.require_user();c stroked_payments.catalog%rowtype;b stroked_payments.bookings%rowtype;e uuid;title text;start_day date;
begin
 if stroked_promotions.is_admin(p_env) then raise exception 'Use Add promotion: administrator promotions are free';end if;
 select * into c from stroked_payments.catalog where environment=p_env and sku=p_sku;
 if not found or c.kind='tip' then raise exception 'Choose an available promotion';end if;
 if not exists(select 1 from stroked_payments.settings where environment=p_env and enabled) or c.payment_link!~'^https://buy[.]stripe[.]com/[A-Za-z0-9_]+$' or (c.payment_link like 'https://buy.stripe.com/test_%')<>(p_env='testing') then raise exception 'Checkout is being prepared. Contact Stroked for help.';end if;
 if jsonb_typeof(p_details)<>'object' or length(p_details::text)>5000 then raise exception 'Invalid booking details';end if;
 title:=left(trim(coalesce(p_details->>'title','')),100);if length(title)<3 then raise exception 'Enter the promotion or business name';end if;
 if coalesce(p_details->>'start_date','')!~'^\d{4}-\d{2}-\d{2}$' then raise exception 'Choose a valid start date';end if;
 start_day:=(p_details->>'start_date')::date;if start_day<(now() at time zone 'America/Halifax')::date or start_day>current_date+366 then raise exception 'Choose a start date within the coming year';end if;
 if coalesce(p_details->>'website','')<>'' and (p_details->>'website')!~'^https://[^[:space:]]+$' then raise exception 'Use a secure https website';end if;
 if c.kind='event' then
  e:=nullif(p_details->>'event_id','')::uuid;
  if p_env='production' then
   if not exists(select 1 from public.stroked_v5_events where id=e and created_by=u and status='approved') then raise exception 'Choose one of your approved events';end if;
  else
   if not exists(select 1 from stroked_v55_testing.events where id=e and created_by=u and status='approved') then raise exception 'Choose one of your approved events';end if;
  end if;
 end if;
 if (select count(*) from stroked_payments.bookings where user_id=u and created_at>now()-interval '1 hour')>=20 then raise exception 'Too many recent bookings. Use an existing booking or try later.';end if;
 insert into stroked_payments.bookings(environment,sku,user_id,event_id,title,website,notes,preferred_start,amount_cents)
 values(p_env,c.sku,u,e,title,left(trim(coalesce(p_details->>'website','')),500),left(trim(coalesce(p_details->>'notes','')),1000),start_day,c.amount_cents) returning * into b;
 return jsonb_build_object('order_id',b.id,'amount_cents',b.amount_cents,'checkout_url',c.payment_link||'?client_reference_id='||b.id::text);
end $$;
create function stroked_payments.list_bookings(p_env text,p_admin boolean default false) returns setof jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid:=stroked_payments.require_user();begin
 if p_admin and not stroked_promotions.is_admin(p_env) then raise exception 'Administrator only' using errcode='42501';end if;
 return query select jsonb_build_object('id',b.id,'sku',b.sku,'title',b.title,'event_id',b.event_id,'website',b.website,'notes',b.notes,'preferred_start',b.preferred_start,'amount_cents',b.amount_cents,'payment_status',b.payment_status,'status',b.status,'promotion_id',b.promotion_id,'starts_on',b.starts_on,'ends_on',b.ends_on,'duration',c.duration,'unit',c.unit,'contact_email',case when p_admin then a.email else null end,'checkout_url',case when s.enabled and c.payment_link<>'' and b.payment_status in ('unpaid','failed') then c.payment_link||'?client_reference_id='||b.id::text else null end)
 from stroked_payments.bookings b join stroked_payments.catalog c on(c.environment,c.sku)=(b.environment,b.sku) join stroked_payments.settings s on s.environment=b.environment left join auth.users a on a.id=b.user_id where b.environment=p_env and(p_admin or b.user_id=u) order by b.created_at desc limit 250;
 if p_admin then return query select jsonb_build_object('id',r.session_id,'sku',r.sku,'title','Payment requires review in Stripe','notes','Stripe session: '||r.session_id,'amount_cents',r.amount_cents,'payment_status','review','status','payment_review') from stroked_payments.receipts r join stroked_payments.catalog c on(c.environment,c.sku)=(r.environment,r.sku) where r.environment=p_env and r.status='review' order by r.created_at desc limit 100;end if;
end $$;
create function stroked_payments.webhook_secret(p_env text) returns text language plpgsql stable security definer set search_path='' as $$
declare result text;begin if p_env not in ('production','testing') then raise exception 'Invalid environment';end if;select decrypted_secret into result from vault.decrypted_secrets where name='stroked_stripe_webhook_'||p_env;if result is null then raise exception 'Webhook not configured';end if;return result;end $$;

create function stroked_payments.accept_event(p_env text,p_event jsonb) returns text language plpgsql security definer set search_path='' as $$
declare obj jsonb:=p_event#>'{data,object}';typ text:=p_event->>'type';c stroked_payments.catalog%rowtype;b stroked_payments.bookings%rowtype;session text;intent text;amount integer;state text;bid uuid;changed integer;
begin
 if p_env not in ('production','testing') or coalesce((p_event->>'livemode')::boolean,false)<>(p_env='production') then return 'ignored_environment';end if;
 if coalesce(p_event->>'id','')!~'^evt_[A-Za-z0-9_]+$' then raise exception 'Invalid event identifier';end if;
 if typ not in ('checkout.session.completed','checkout.session.async_payment_succeeded','checkout.session.async_payment_failed','checkout.session.expired','charge.refunded','charge.dispute.created') then return 'ignored_type';end if;
 insert into stroked_payments.processed_events(id,event_type) values(p_event->>'id',typ) on conflict do nothing;get diagnostics changed=row_count;if changed=0 then return 'duplicate_event';end if;
 if typ in ('charge.refunded','charge.dispute.created') then
  intent:=obj->>'payment_intent';if intent is null then return 'ignored_reversal';end if;
  insert into stroked_payments.reversals(payment_intent,reason) values(intent,typ) on conflict do nothing;
  update stroked_payments.receipts set status='review' where payment_intent=intent and environment=p_env;
  update stroked_payments.bookings x set payment_status='review',status='payment_review' from stroked_payments.receipts r where r.payment_intent=intent and r.environment=p_env and x.stripe_session=r.session_id;
  update stroked_promotions.promotions p set payload=jsonb_set(p.payload,'{active}','false'::jsonb),updated_at=now() from stroked_payments.bookings x where x.promotion_id=p.id and x.environment=p_env and x.payment_status='review';
  return 'reversal_recorded';
 end if;
 select * into c from stroked_payments.catalog where environment=p_env and payment_link_id=obj->>'payment_link' and payment_link_id<>'';
 if not found then return 'ignored_payment_link';end if;
 session:=obj->>'id';intent:=obj->>'payment_intent';amount:=coalesce((obj->>'amount_total')::integer,0);
 if session!~'^cs_[A-Za-z0-9_]+$' then raise exception 'Invalid checkout identifier';end if;
 state:=case when typ in ('checkout.session.async_payment_failed','checkout.session.expired') then 'failed' when obj->>'payment_status'='paid' then 'paid' else 'pending' end;
 if (obj->>'currency') is distinct from 'cad' or (obj->>'mode') is distinct from 'payment' or coalesce((obj#>>'{total_details,amount_tax}')::integer,0)<>0 or amount<>coalesce((obj->>'amount_subtotal')::integer,amount) or(c.kind<>'tip' and amount<>c.amount_cents) or(c.kind='tip' and amount<100) or exists(select 1 from stroked_payments.reversals where payment_intent=intent) then state:='review';end if;
 if c.kind<>'tip' then
  if coalesce(obj->>'client_reference_id','')~'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
   select * into b from stroked_payments.bookings where id=(obj->>'client_reference_id')::uuid and environment=p_env and sku=c.sku for update;
  end if;
  if b.id is null or b.amount_cents<>amount then state:='review';else bid:=b.id;if b.payment_status='paid' and b.stripe_session is distinct from session then state:='review';end if;end if;
 end if;
 insert into stroked_payments.receipts(session_id,environment,sku,booking_id,payment_intent,amount_cents,status) values(session,p_env,c.sku,bid,intent,amount,state)
 on conflict(session_id) do update set status=case when stroked_payments.receipts.status='review' then 'review' when stroked_payments.receipts.status='paid' and excluded.status in ('pending','failed') then 'paid' else excluded.status end;
 if bid is not null then
  if state='paid' then update stroked_payments.bookings set payment_status='paid',status=case when status='published' then status else 'awaiting_publication' end,stripe_session=session,paid_at=coalesce(paid_at,now()) where id=bid and payment_status<>'review';
  elsif state='failed' then update stroked_payments.bookings set payment_status='failed' where id=bid and payment_status='unpaid';
  elsif state='review' and b.stripe_session is not distinct from session then update stroked_payments.bookings set payment_status='review',status='payment_review' where id=bid;end if;
 end if;
 return state;
end $$;

create function stroked_payments.fulfill_booking(p_env text,p_booking uuid,p_payload jsonb,p_id uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_promotions.require_admin(p_env);b stroked_payments.bookings%rowtype;c stroked_payments.catalog%rowtype;p jsonb:=p_payload;result uuid;start_day date;end_day date;
begin
 select * into b from stroked_payments.bookings where id=p_booking and environment=p_env for update;
 if not found or b.payment_status<>'paid' or b.paid_at is null then raise exception 'A Stripe-confirmed payment is required';end if;
 if b.promotion_id is not null then return b.promotion_id;end if;
 select * into c from stroked_payments.catalog where environment=b.environment and sku=b.sku;
 start_day:=(p->>'start_date')::date;end_day:=(p->>'end_date')::date;
 if start_day<greatest(b.preferred_start,(now() at time zone 'America/Halifax')::date) or end_day is distinct from stroked_payments.campaign_end(start_day,c.duration,c.unit) then raise exception 'Give this booking its full paid duration from the confirmed start date';end if;
 if c.kind='event' and coalesce(p->>'event_id','')<>b.event_id::text then raise exception 'Use the event linked to this payment';end if;
 if c.sku like 'featured_event_%' or c.sku like 'featured_business_%' then p:=p||'{"featured":true}'::jsonb;end if;
 if c.sku like 'enhanced_event_%' then if jsonb_array_length(coalesce(p->'photos','[]'::jsonb))<1 then raise exception 'Add approved gallery photographs before publishing this upgrade';end if;p:=p||'{"enhanced":true}'::jsonb;end if;
 if c.sku like 'sponsor_spotlight_%' then p:=p||'{"spotlight":true}'::jsonb;end if;
 result:=stroked_promotions.save(p_env,p,p_id);
 update stroked_payments.bookings set status='published',promotion_id=result,starts_on=start_day,ends_on=end_day where id=b.id;
 return result;
end $$;

-- Public wrappers are invokers; private implementations expose only the required operations.
do $$declare env text;prefix text;begin
 foreach env in array array['production','testing'] loop prefix:=case when env='production' then 'stroked_live_v55_' else 'stroked_v55_' end;
 execute format('create function public.%I() returns setof jsonb language sql stable security invoker set search_path='''' as $f$select * from stroked_payments.public_catalog(%L)$f$',prefix||'promotion_catalog',env);
 execute format('create function public.%I(p_sku text,p_details jsonb) returns jsonb language sql security invoker set search_path='''' as $f$select stroked_payments.create_booking(%L,p_sku,p_details)$f$',prefix||'create_booking',env);
 execute format('create function public.%I() returns setof jsonb language sql stable security invoker set search_path='''' as $f$select * from stroked_payments.list_bookings(%L,false)$f$',prefix||'my_bookings',env);
 execute format('create function public.%I() returns setof jsonb language sql stable security invoker set search_path='''' as $f$select * from stroked_payments.list_bookings(%L,true)$f$',prefix||'admin_bookings',env);
 execute format('create function public.%I(p_booking uuid,p_payload jsonb,p_id uuid default null) returns uuid language sql security invoker set search_path='''' as $f$select stroked_payments.fulfill_booking(%L,p_booking,p_payload,p_id)$f$',prefix||'fulfill_booking',env);
 execute format('revoke all on function public.%I(),public.%I(text,jsonb),public.%I(),public.%I(),public.%I(uuid,jsonb,uuid) from public,anon',prefix||'promotion_catalog',prefix||'create_booking',prefix||'my_bookings',prefix||'admin_bookings',prefix||'fulfill_booking');
 execute format('grant execute on function public.%I() to anon,authenticated',prefix||'promotion_catalog');
 execute format('grant execute on function public.%I(text,jsonb),public.%I(),public.%I(),public.%I(uuid,jsonb,uuid) to authenticated',prefix||'create_booking',prefix||'my_bookings',prefix||'admin_bookings',prefix||'fulfill_booking');
 end loop;
end $$;
create function public.stroked_stripe_webhook_secret(p_environment text) returns text language sql stable security invoker set search_path='' as $$select stroked_payments.webhook_secret(p_environment)$$;
create function public.stroked_stripe_accept_event(p_environment text,p_event jsonb) returns text language sql security invoker set search_path='' as $$select stroked_payments.accept_event(p_environment,p_event)$$;
revoke all on function public.stroked_stripe_webhook_secret(text),public.stroked_stripe_accept_event(text,jsonb) from public,anon,authenticated;
grant execute on function public.stroked_stripe_webhook_secret(text),public.stroked_stripe_accept_event(text,jsonb) to service_role;
revoke all on all functions in schema stroked_payments from public,anon,authenticated;
grant usage on schema stroked_payments to anon,authenticated,service_role;
grant execute on function stroked_payments.public_catalog(text) to anon,authenticated;
grant execute on function stroked_payments.require_user(),stroked_payments.campaign_end(date,integer,text),stroked_payments.create_booking(text,text,jsonb),stroked_payments.list_bookings(text,boolean),stroked_payments.fulfill_booking(text,uuid,jsonb,uuid) to authenticated;
grant execute on all functions in schema stroked_payments to service_role;
notify pgrst,'reload schema';
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
  return result||jsonb_build_object('event_id',coalesce(linked::text,''),'start_date',start_on::text,'end_date',coalesce(end_on::text,''),
    'cover',stroked_promotions.media_path(p->>'cover',p_environment),'photos',photos,'sponsor_image',stroked_promotions.media_path(p->>'sponsor_image',p_environment));
end $$;


commit;
