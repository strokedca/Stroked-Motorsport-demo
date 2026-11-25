import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {PGlite} from '@electric-sql/pglite';
const read=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const id=n=>'12345678-0000-4000-8000-'+String(n).padStart(12,'0');
test('end dates preserve image checks and RSVP availability; engagement counters are private, deduplicated and accurate',async()=>{
 const pg=new PGlite();
 try{
  for(const file of ['tests/fixtures/live-v54-schema.sql','supabase/migrations/20261111_v55_testing.sql','supabase/migrations/20261111205005_v55_production.sql'])await pg.exec(await read(file));
  await pg.exec(`create table stroked_live_v55.member_blocks(user_id uuid primary key);create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;grant usage on schema storage to anon,authenticated;grant select,insert on storage.objects to authenticated;grant select on storage.objects to anon;
  create table auth.mfa_factors(user_id uuid,factor_type text,status text);create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;create schema stroked_promotions;`);
  for(const file of ['supabase/fixes/organizer_event_images.sql','supabase/fixes/administrator_mfa.sql','supabase/migrations/20261123174000_site_traffic.sql','supabase/migrations/20261125123000_event_date_ranges.sql','supabase/migrations/20261125124000_event_engagement.sql'])await pg.exec(await read(file));
  for(const n of [1,2])await pg.query('insert into auth.users values($1,now(),$2)',[id(n),{account_type:'organizer'}]);
  await pg.query('insert into public.event_admins(user_id) values($1)',[id(2)]);
  await pg.query("insert into auth.mfa_factors values($1,'totp','verified')",[id(2)]);await pg.query('insert into stroked_live_v55.admin_security(user_id) values($1)',[id(2)]);
  async function actor(n,aal='aal1'){await pg.exec('reset role');await pg.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[n?id(n):'',JSON.stringify({sub:n?id(n):'',aal})]);await pg.exec(n?'set role authenticated':'set role anon');}
  const today=(await pg.query("select (now() at time zone 'America/Halifax')::date::text as today_day")).rows[0].today_day;
  const start=new Date(today+'T12:00:00Z');start.setUTCDate(start.getUTCDate()-2);const yesterday=start.toISOString().slice(0,10);
  const payload={name:'Ongoing test ride',club:'Test club',province:'Prince Edward Island',city:'Summerside',date:yesterday,endDate:today,categories:['Motorcycles']};
  await actor(1);const event=(await pg.query('select public.stroked_live_v55_submit($1) id',[payload])).rows[0].id;
  await assert.rejects(()=>pg.query('select public.stroked_live_v55_submit($1)',[{...payload,endDate:'2026-02-30'}]),/date|End date/i);
  await assert.rejects(()=>pg.query('select public.stroked_live_v55_submit($1)',[{...payload,endDate:yesterday.slice(0,8)+'01'}]),/End date|earlier/i);
  await assert.rejects(()=>pg.query('select public.stroked_live_v55_submit($1)',[{...payload,cover:'production/'+id(2)+'/'+id(9)+'.jpg'}]),/uploaded/);
  await pg.exec('reset role');const stored=(await pg.query('select payload from public.stroked_v5_events where id=$1',[event])).rows[0].payload;
  assert.equal(stored.endDate,today);assert.equal(stored.province,'PEI');
  await pg.query("update public.stroked_v5_events set status='approved' where id=$1",[event]);
  await actor(1);await pg.query("select public.stroked_live_v55_save_rsvp($1,'going',0)",[event]);await pg.query("select public.stroked_live_v55_save_rsvp($1,'going',0)",[event]);await pg.query("select public.stroked_live_v55_save_rsvp($1,'interested',0)",[event]);
  const stats=()=>pg.query('select public.stroked_live_v55_admin_engagement_stats() value');
  await assert.rejects(stats,/Administrator only/);await assert.rejects(()=>pg.query('select * from stroked_analytics.action_daily'),/permission denied/);
  await actor(2);await assert.rejects(stats,/Administrator only/);
  await actor(2,'aal2');let report=(await stats()).rows[0].value;
  assert.equal(report.days.find(r=>r.action==='account_setup').total,1);assert.equal(report.days.find(r=>r.action==='rsvp_save').total,2);
  await pg.exec('reset role;set role service_role');
  const action=async(receipt,user=null,target=event,campaign='peisa')=>(await pg.query('select public.stroked_record_event_action($1,$2,$3,$4,$5,$6,$7,$8) accepted',[id(receipt),id(3),'a'.repeat(64),'facebook','event_open',target,campaign,user])).rows[0].accepted;
  assert.equal(await action(10),true);assert.equal(await action(10),false);assert.equal(await action(11,id(2)),false);assert.equal(await action(12,null,id(99)),false);
  await assert.rejects(()=>action(13,null,event,'member@example.com'),/Invalid event action/);
  await actor(2,'aal2');report=(await stats()).rows[0].value;assert.equal(report.days.find(r=>r.action==='event_open').total,1);
  assert.doesNotMatch(JSON.stringify(report),/visitor_id|user_id|email|network_hash/);
  await pg.exec('reset role');await pg.query("update public.stroked_v5_events set payload=jsonb_set(payload,'{endDate}',to_jsonb($2::text)) where id=$1",[event,yesterday]);
  await actor(1);await assert.rejects(()=>pg.query("select public.stroked_live_v55_save_rsvp($1,'going',0)",[event]),/not available/);
  await pg.query("select public.stroked_live_v55_save_rsvp($1,'not_going',0)",[event]);
 }finally{await pg.close();}
});
