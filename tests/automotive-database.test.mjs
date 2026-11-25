import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile,readdir} from 'node:fs/promises';import {PGlite} from '@electric-sql/pglite';
const read=p=>readFile(new URL('../'+p,import.meta.url),'utf8'),id=n=>'12345678-0000-4000-8000-'+String(n).padStart(12,'0');
test('automotive migration preserves listings, image checks and alert scope without emailing the taxonomy backfill',async()=>{
 const pg=new PGlite();try{
  await pg.exec(await read('tests/fixtures/live-v54-schema.sql'));
  await pg.exec("alter table auth.users add column email text;alter table auth.users add column deleted_at timestamptz;create schema extensions;create function extensions.gen_random_bytes(n integer) returns bytea language sql as $$select decode(repeat('ab',n),'hex')$$;create schema vault;create table vault.secrets(name text,decrypted_secret text);create view vault.decrypted_secrets as select * from vault.secrets;create function vault.create_secret(s text,n text) returns void language sql as $$insert into vault.secrets values(n,s)$$;");
  for(const f of ['20261111_v55_testing.sql','20261111205005_v55_production.sql','20261118010000_rsvp_email_alerts.sql'])await pg.exec(await read('supabase/migrations/'+f));
  await pg.exec('create table stroked_live_v55.member_blocks(user_id uuid primary key);create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;grant usage on schema storage to anon,authenticated;grant select,insert on storage.objects to authenticated;grant select on storage.objects to anon;');
  for(const f of ['supabase/fixes/follows_and_discovery_emails.sql','supabase/fixes/organizer_event_images.sql','supabase/migrations/20261112002003_admin_site_promotions.sql','supabase/migrations/20261117233000_promotion_categories.sql','supabase/migrations/20261125123000_event_date_ranges.sql'])await pg.exec(await read(f));
  for(const n of [1,2])await pg.query('insert into auth.users(id,email_confirmed_at,raw_user_meta_data,email) values($1,now(),$2,$3)',[id(n),{account_type:'organizer'},'test'+n+'@example.test']);
  const today=(await pg.query("select (now() at time zone 'America/Halifax')::date::text as today_day")).rows[0].today_day;
  const base={name:'Classic show',club:'Club',city:'Town',province:'PEI',date:today,categories:['Classic cars'],status:'Scheduled',details:'Original details',endDate:today,photos:[]};
  const rows=[base,{...base,name:'Atlantic Truck Show',club:'Atlantic Provinces Trucking Association / Marketplace Events',date:'2027-05-07',endDate:'2027-05-08',categories:['Cars & trucks']},{...base,name:'Atlantic Nationals Automotive Extravaganza',club:'Atlantic Nationals',date:'2027-07-07',endDate:'2027-07-11',categories:['Classic cars','Cars & trucks']},{...base,name:'Radical Speed Sport',club:'Radical Speed Sport',date:'2027-04-16',endDate:'2027-04-18',categories:['Classic cars','Motorcycles']},{...base,name:'Unrelated ride',categories:['Motorcycles']}];
  for(let n=0;n<rows.length;n++)await pg.query("insert into public.stroked_v5_events(id,created_by,payload,status) values($1,$2,$3,'approved')",[id(10+n),id(1),rows[n]]);
  await pg.query("insert into stroked_alerts.subscriptions(user_id,new_events,follow_emails,categories) values($1,true,true,'[\"Classic cars\"]'),($2,true,true,'[\"Cars & trucks\"]')",[id(1),id(2)]);
  await pg.query('insert into stroked_alerts.event_follows values($1,$2)',[id(1),id(10)]);
  const before=(await pg.query('select count(*)::int n from stroked_alerts.outbox')).rows[0].n;
  const migration=(await readdir(new URL('../supabase/migrations/',import.meta.url))).find(n=>n.endsWith('_automotive_vehicle_focus.sql'));await pg.exec(await read('supabase/migrations/'+migration));
  assert.equal((await pg.query('select count(*)::int n from stroked_alerts.outbox')).rows[0].n,before);
  assert.equal((await pg.query("select tgenabled from pg_trigger where tgname='stroked_email_event_changed'")).rows[0].tgenabled,'O');
  const stored=(await pg.query('select payload from public.stroked_v5_events order by id')).rows.map(r=>r.payload);
  assert.equal(stored.length,5);assert.deepEqual(stored[0].categories,['Cars & trucks','Classic cars']);assert.deepEqual(stored[0].vehicleFocus,['Classic & Antique']);assert.equal(stored[0].details,base.details);assert.equal(stored[0].endDate,today);
  assert.deepEqual(stored[1].vehicleFocus,['Commercial & Heavy Vehicles']);assert.deepEqual(stored[2].vehicleFocus,['Classic & Antique','Custom & Modified']);assert.deepEqual(stored[3].vehicleFocus,['Classic & Antique','Custom & Modified']);assert.deepEqual(stored[4],rows[4]);
  const validate=async p=>(await pg.query('select stroked_live_v55.valid_payload($1) p',[p])).rows[0].p;
  const custom=await validate({...base,categories:['Cars & trucks'],vehicleFocus:['Modern','Custom & Modified']});assert.deepEqual(custom.vehicleFocus,['Modern','Custom & Modified']);assert.deepEqual(custom.categories,['Cars & trucks']);
  const clear=await validate({...base,vehicleFocus:[]});assert.deepEqual(clear.categories,['Cars & trucks']);assert.deepEqual(clear.vehicleFocus,[]);
  assert.deepEqual((await validate({...base,categories:['Motorcycles'],vehicleFocus:['Modern']})).vehicleFocus,[]);
  for(const value of [null,'Modern',{},['Other'],[null],[{}],['Modern','Modern','Modern','Modern','Modern']])await assert.rejects(()=>validate({...base,vehicleFocus:value}),/valid Cars & Trucks interests/);
  const classic=stored[0],truck=stored[1];for(const [member,p,expected]of [[1,classic,true],[1,truck,false],[2,classic,true],[2,truck,true]])assert.equal((await pg.query('select stroked_alerts.matches(s,$2) result from stroked_alerts.subscriptions s where user_id=$1',[id(member),p])).rows[0].result,expected);
  assert.deepEqual((await pg.query('select categories from stroked_alerts.subscriptions where user_id=$1',[id(1)])).rows[0].categories,['Classic cars']);
  await pg.query("select set_config('request.jwt.claim.sub',$1,false)",[id(1)]);await pg.exec('set role authenticated');
  const newId=(await pg.query('select public.stroked_live_v55_submit($1) id',[{...base,categories:['Cars & trucks'],vehicleFocus:['Classic & Antique','Custom & Modified']}])).rows[0].id;
  await assert.rejects(()=>pg.query('select public.stroked_live_v55_submit($1)',[{...base,cover:'production/'+id(2)+'/'+id(99)+'.jpg'}]),/uploaded/);
  await pg.exec('reset role');assert.deepEqual((await pg.query('select payload from public.stroked_v5_events where id=$1',[newId])).rows[0].payload.vehicleFocus,['Classic & Antique','Custom & Modified']);
  await pg.query("update public.stroked_v5_events set payload=jsonb_set(payload,'{time}','\"12:00\"') where id=$1",[id(10)]);assert.ok((await pg.query("select count(*)::int n from stroked_alerts.outbox where kind='event_update'")).rows[0].n>0,'real later updates must still queue alerts');
  const promo={title:'Car and truck promotion',kind:'Business advertisement',start_date:today,categories:['Cars & trucks'],photos:[]};assert.deepEqual((await pg.query("select stroked_promotions.valid_payload($1,'production') p",[promo])).rows[0].p.categories,['Cars & trucks']);
  await pg.exec('set role anon');await assert.rejects(()=>pg.query('select stroked_live_v55.with_vehicle_focus($1,$1)',[base]),/permission denied/);
 }finally{await pg.close();}
});
