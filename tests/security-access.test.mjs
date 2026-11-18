import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {PGlite} from '@electric-sql/pglite';
import {buildSite} from '../scripts/build-site.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');

test('legacy administration and private image reads reject blocked, unverified and deleted identities',async()=>{
 const pg=new PGlite(),id=n=>'94000000-0000-4000-8000-'+String(n).padStart(12,'0');
 async function actor(n){await pg.exec('reset role');await pg.query("select set_config('request.jwt.claim.sub',$1,false)",[n?id(n):'']);await pg.exec(n?'set role authenticated':'set role anon');}
 try{
  await pg.exec(await read('./fixtures/live-v54-schema.sql'));
  for(const f of ['20261111_v55_testing.sql','20261111205005_v55_production.sql'])await pg.exec(await read('../supabase/migrations/'+f));
  await pg.exec(`create table public.events(id uuid,status text,created_at timestamptz default now(),submitted_by uuid);
    alter table public.events enable row level security;grant select on public.events to anon,authenticated;
    create policy legacy_public on public.events for select to anon,authenticated using(status='approved');
    create table stroked_live_v55.member_blocks(user_id uuid primary key);
    create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);
    alter table storage.objects enable row level security;grant usage on schema storage to anon,authenticated;
    grant select,insert on storage.objects to authenticated;grant select on storage.objects to anon;`);
  await pg.exec(await read('../supabase/migrations/20261112002003_admin_site_promotions.sql'));
  await pg.exec(await read('../supabase/fixes/organizer_event_images.sql'));
  const fix=await read('../supabase/fixes/security_access_review.sql');await pg.exec(fix);
  for(const n of [1,2,3])await pg.query('insert into auth.users values($1,$2,$3)',[id(n),n===3?null:new Date().toISOString(),{account_type:'organizer',is_admin:true}]);
  await pg.query('insert into public.event_admins(user_id) values($1),($2)',[id(1),id(3)]);
  const privatePath='production/'+id(2)+'/'+id(8)+'.jpg';
  await pg.query("insert into storage.objects(bucket_id,name) values('stroked-event-images',$1)",[privatePath]);
  await actor(null);await assert.rejects(()=>pg.query('select * from public.events'),/permission denied/);
  await actor(2);assert.equal((await pg.query('select * from storage.objects')).rows.length,1);
  for(const fn of ['admin_pending_events','get_pending_events'])await assert.rejects(()=>pg.query('select * from public.'+fn+'()'),/Administrator access required/);
  await pg.exec('reset role');await pg.query('delete from auth.users where id=$1',[id(2)]);
  await actor(2);assert.equal((await pg.query('select * from storage.objects')).rows.length,0,'a stale JWT cannot read private uploads after account deletion');
  await actor(3);assert.equal((await pg.query('select public.is_event_admin() ok')).rows[0].ok,false);
  await assert.rejects(()=>pg.query('select * from public.get_pending_events()'),/verified email/);
  await actor(1);assert.equal((await pg.query("select stroked_promotions.is_admin('production') ok")).rows[0].ok,true);
  assert.equal((await pg.query('select * from storage.objects')).rows.length,1);
  await pg.exec('reset role');await pg.query('insert into stroked_live_v55.member_blocks values($1)',[id(1)]);
  await actor(1);assert.equal((await pg.query('select public.is_event_admin() ok')).rows[0].ok,false);
  assert.equal((await pg.query("select stroked_promotions.is_admin('production') ok")).rows[0].ok,false);
  assert.equal((await pg.query('select * from storage.objects')).rows.length,0);
  await assert.rejects(()=>pg.query('select * from public.admin_pending_events()'),/blocked|Administrator/);
  await assert.rejects(()=>pg.query('select * from public.stroked_live_v55_admin_promotions()'),/Administrator only/);
  await pg.exec('reset role');await pg.exec(fix); // Reapplication changes no records.
  assert.equal((await pg.query('select count(*)::int n from storage.objects')).rows[0].n,1);
 }finally{await pg.close();}
});

test('root deployment and generated build share browser protections and integrity-pinned SDKs',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'stroked-security-build-'));
 try{
  await buildSite({mode:'production',outDir:dir});
  const headers=await readFile(join(dir,'_headers'),'utf8');assert.equal(headers,await read('../_headers'));
  for(const value of ["frame-ancestors 'none'","object-src 'none'","base-uri 'self'",'X-Frame-Options: DENY','Strict-Transport-Security: max-age=31536000','X-Content-Type-Options: nosniff','Permissions-Policy: camera=(), microphone=(), geolocation=()'])assert.ok(headers.includes(value),value);
  for(const page of ['index.html','unsubscribe.html']){
   const html=await readFile(join(dir,page),'utf8');
   assert.match(html,/@supabase\/supabase-js@2\.95\.3\/dist\/umd\/supabase.min.js" integrity="sha384-[A-Za-z0-9+/]+" crossorigin="anonymous"/);
   assert.doesNotMatch(html,/@supabase\/supabase-js@2["/]/);
  }
 }finally{await rm(dir,{recursive:true,force:true});}
});
