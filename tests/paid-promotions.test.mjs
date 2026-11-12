import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {PGlite} from '@electric-sql/pglite';
test('bookings use trusted prices, isolate owners, and require verified payment before publication',async()=>{
 const pg=new PGlite(),uid=n=>'70000000-0000-4000-8000-'+String(n).padStart(12,'0');
 async function actor(n,query,args=[]){await pg.exec('reset role');await pg.query("select set_config('request.jwt.claim.sub',$1,false)",[typeof n==='number'?uid(n):'']);await pg.exec(n==='service'?'set role service_role':n?'set role authenticated':'set role anon');return(await pg.query(query,args)).rows;}
 async function call(n,name,args=[]){return(await actor(n,'select public.stroked_live_v55_'+name+'('+args.map((_,i)=>'$'+(i+1)).join(',')+') as value',args)).map(r=>r.value);}
 async function event(payload){return(await actor('service','select public.stroked_stripe_accept_event($1,$2) as value',['production',payload]))[0].value;}
 try{
  await pg.exec(await readFile(new URL('./fixtures/live-v54-schema.sql',import.meta.url),'utf8'));
  await pg.exec('alter table auth.users add column email text;');
  for(const n of [1,2,3])await pg.query('insert into auth.users(id,email_confirmed_at,raw_user_meta_data,email) values($1,now(),$2,$3)',[uid(n),{account_type:'organizer',is_admin:true},'person'+n+'@example.test']);
  await pg.query('insert into public.event_admins(user_id) values($1)',[uid(1)]);
  await pg.exec(await readFile(new URL('../supabase/migrations/20261111_v55_testing.sql',import.meta.url),'utf8'));
  await pg.exec(await readFile(new URL('../supabase/migrations/20261111205005_v55_production.sql',import.meta.url),'utf8'));
  await pg.exec('create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant insert on storage.objects to authenticated;');
  await pg.exec(await readFile(new URL('../supabase/migrations/20261112002003_admin_site_promotions.sql',import.meta.url),'utf8'));
  await pg.exec(await readFile(new URL('../supabase/migrations/20261112011549_paid_promotions_and_stripe_receipts.sql',import.meta.url),'utf8'));
  assert.equal((await call(null,'promotion_catalog')).length,16);
  await pg.exec('reset role');
  const day=(await pg.query("select (now() at time zone 'America/Halifax')::date::text as day")).rows[0].day;
  await pg.exec("update stroked_payments.catalog set payment_link='https://buy.stripe.com/fixture_'||sku,payment_link_id='plink_'||sku where environment='production';update stroked_payments.settings set enabled=true where environment='production';");
  const details={title:'Local business',website:'https://example.test',start_date:day,notes:'Supplied artwork follows',amount_cents:1};
  await assert.rejects(()=>call(null,'create_booking',['business_card_3',details]),/permission denied/);
  await assert.rejects(()=>call(1,'create_booking',['business_card_3',details]),/administrator promotions are free/);
  const booking=(await call(2,'create_booking',['business_card_3',details]))[0];assert.equal(booking.amount_cents,6500,'the browser cannot choose its own price');assert.ok(booking.checkout_url.endsWith(booking.order_id));
  assert.deepEqual(await call(3,'my_bookings'),[]);assert.equal((await call(2,'my_bookings')).length,1);await assert.rejects(()=>call(2,'admin_bookings'),/Administrator only/);
  await assert.rejects(()=>actor(2,'select * from stroked_payments.bookings'),/permission denied/);
  await assert.rejects(()=>actor(2,"select public.stroked_stripe_webhook_secret('production')"),/permission denied/);
  await assert.rejects(()=>actor(2,"select public.stroked_stripe_accept_event('production','{}')"),/permission denied/);
  const checkout=(id,type,order=booking,extra={})=>({id,type,livemode:true,data:{object:{id:'cs_live_'+order.order_id.replaceAll('-',''),mode:'payment',currency:'cad',amount_total:order.amount_cents,amount_subtotal:order.amount_cents,total_details:{amount_tax:0},payment_link:'plink_business_card_3',payment_intent:'pi_'+order.order_id.replaceAll('-',''),client_reference_id:order.order_id,payment_status:'paid',...extra}}});
  const unpaid=checkout('evt_unpaid','checkout.session.completed',booking,{payment_status:'unpaid'});assert.equal(await event(unpaid),'pending');assert.equal((await call(2,'my_bookings'))[0].payment_status,'unpaid');assert.equal(await event(unpaid),'duplicate_event');
  const published={kind:'Business advertisement',title:'Local business',description:'Approved advertisement',link:'https://example.test',start_date:day,end_date:'',featured:false,enhanced:false,spotlight:false,active:true,photos:[]};
  await assert.rejects(()=>call(1,'fulfill_booking',[booking.order_id,published,null]),/Stripe-confirmed payment/);
  assert.equal(await event(checkout('evt_paid','checkout.session.async_payment_succeeded')),'paid');assert.equal((await call(2,'my_bookings'))[0].payment_status,'paid');
  await assert.rejects(()=>call(2,'fulfill_booking',[booking.order_id,published,null]),/Administrator only/);
  await pg.exec('reset role');published.end_date=(await pg.query("select stroked_payments.campaign_end($1::date,3,'month')::text as day",[day])).rows[0].day;
  const promotion=(await call(1,'fulfill_booking',[booking.order_id,published,null]))[0];assert.ok(promotion);assert.equal((await call(1,'fulfill_booking',[booking.order_id,published,null]))[0],promotion,'a repeated publication does not create another promotion');assert.equal((await call(2,'my_bookings'))[0].status,'published');
  const bad=(await call(2,'create_booking',['business_card_3',details]))[0];assert.equal(await event(checkout('evt_bad_currency','checkout.session.completed',bad,{currency:'usd'})),'review');await assert.rejects(()=>call(1,'fulfill_booking',[bad.order_id,published,null]),/Stripe-confirmed payment/);
  const badAmount=(await call(2,'create_booking',['business_card_3',details]))[0];assert.equal(await event(checkout('evt_bad_amount','checkout.session.completed',badAmount,{amount_total:1,amount_subtotal:1})),'review');
  const earlierRefund=(await call(2,'create_booking',['business_card_3',details]))[0];const incoming=checkout('evt_after_refund','checkout.session.completed',earlierRefund);assert.equal(await event({id:'evt_early_refund',type:'charge.refunded',livemode:true,data:{object:{payment_intent:incoming.data.object.payment_intent}}}),'reversal_recorded');assert.equal(await event(incoming),'review','a refund delivered first cannot later become a paid booking');
  assert.equal(await event({id:'evt_refund',type:'charge.refunded',livemode:true,data:{object:{payment_intent:checkout('evt_x','checkout.session.completed').data.object.payment_intent}}}),'reversal_recorded');assert.equal((await call(2,'my_bookings')).find(b=>b.id===booking.order_id).payment_status,'review');
  await pg.exec('reset role');assert.equal((await pg.query('select (payload->>\'active\')::boolean as active from stroked_promotions.promotions where id=$1',[promotion])).rows[0].active,false,'refunds remove the paid placement from public display');
  const test=(await call(null,'promotion_catalog')).every(c=>c.currency==='cad');assert.equal(test,true);
 }finally{await pg.close();}
});
